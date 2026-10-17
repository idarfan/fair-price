"""House PTR／年報（Schedule A）PDF 解析 sidecar。

用法：house_parser.py --kind ptr|annual --ranges config/hall_of_fame_ranges.yml <pdf>
輸出一個 JSON 物件到 stdout：
  {"status": "parsed"|"needs_review", "reasons": [...], "marker_count": n, "rows": [...]}
解析不到東西不丟例外，一律以 needs_review＋reasons 回報；只有程式錯誤才以非 0 結束。

新格式 PDF 的小型大寫標題（FILING STATUS、DESCRIPTION、SCHEDULE A…）在文字層只剩
首字母＋\\x00（例如 "F\\x00\\x00\\x00\\x00\\x00"），舊格式則是大小寫混雜的原字（"FIlINg STaTuS:"）。
"""
import argparse
import json
import math
import re
import sys
from datetime import datetime

import pdfplumber
import yaml

LINE_TOLERANCE = 2.5
COLUMN_TOLERANCE = 4
DATE_COLUMN_TOLERANCE = 15
MIN_TEXT_CHARS = 200
DATE_RE = re.compile(r"^\d{1,2}/\d{1,2}/\d{4}$")
TICKER_RE = re.compile(r"\(([A-Z][A-Z0-9.\-]{0,9})\)")
TYPE_CODE_RE = re.compile(r"\[([A-Z0-9]{2,3})\]")
TYPE_CODE_TOKEN_RE = re.compile(r"\[[A-Z0-9]{2,3}\]$")
MARKER_MAX_TOKENS = 6
MARKER_WORDS = {
    "filingstatus": "FS", "description": "D", "subholdingof": "SO",
    "location": "L", "comments": "C",
}
EXACT_AMOUNT_RE = re.compile(r"^\$(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)$")
VALUE_START_RE = re.compile(r"^(\$|None\b|Over\b|Spouse/DC\b|Undetermined\b)")
TX_TYPES = {"P": "P", "S": "S", "S (partial)": "S_partial", "E": "E"}


# ---------- 文字層 → 行 ----------

def clean(text):
    return text.replace("\x00", "")


def is_bold(word):
    return "bold" in word.get("fontname", "").lower()


def page_lines(page):
    words = page.extract_words(extra_attrs=["fontname", "size"], use_text_flow=False)
    lines = []
    for word in sorted(words, key=lambda w: (round(w["top"]), w["x0"])):
        if lines and abs(lines[-1][0]["top"] - word["top"]) <= LINE_TOLERANCE:
            lines[-1].append(word)
        else:
            lines.append([word])
    return [sorted(line, key=lambda w: w["x0"]) for line in lines]


def line_text(words):
    return " ".join(clean(w["text"]) for w in words).strip()


def marker(words):
    """回傳 (代號, 冒號後文字)；不是標記行則 None。標籤最多 MARKER_MAX_TOKENS 個 token。"""
    label_words = []
    for index, word in enumerate(words[:MARKER_MAX_TOKENS]):
        head, colon, tail = word["text"].partition(":")
        label_words.append(head)
        if colon:
            rest = ([tail] if tail else []) + [w["text"] for w in words[index + 1:]]
            return _marker_key(label_words), clean(" ".join(rest)).strip()
    return None


def _marker_key(label_words):
    tokens = [t for t in label_words if t]
    if not tokens:
        return None
    if any("\x00" in t for t in tokens):
        return "".join(t[0].upper() for t in tokens)
    return MARKER_WORDS.get("".join(clean(t).lower() for t in tokens))


def is_heading(words):
    return all(is_bold(w) for w in words) and max(w["size"] for w in words) >= 11


def in_column(word, start, end):
    return start - COLUMN_TOLERANCE <= word["x0"] < (end - COLUMN_TOLERANCE if end else 1e9)


def column_text(words, start, end):
    return " ".join(clean(w["text"]) for w in words if in_column(w, start, end)).strip()


# ---------- 共用 ----------

class Ranges:
    def __init__(self, path):
        with open(path, encoding="utf-8") as fh:
            self.table = {row["label"]: (row["min"], row["max"]) for row in yaml.safe_load(fh)}

    def lookup(self, label):
        if label in self.table:
            return self.table[label]
        exact = EXACT_AMOUNT_RE.match(label)
        if exact:
            value = float(exact.group(1).replace(",", ""))
            return math.floor(value), math.ceil(value)
        return None


def iso_date(text):
    try:
        return datetime.strptime(text, "%m/%d/%Y").date().isoformat()
    except (TypeError, ValueError):
        return None


def asset_parts(asset_name):
    tickers = TICKER_RE.findall(asset_name)
    codes = TYPE_CODE_RE.findall(asset_name)
    return (tickers[-1] if tickers else None), (codes[-1] if codes else None)


OWNERS = ("SP", "JT", "DC")


def owner_value(text, reasons, number):
    if not text:
        return "self"
    if text not in OWNERS:
        reasons.append(f"第 {number} 列未知持有人代碼：{text!r}")
    return text


class TokenStream:
    """文字層 token 序列；檢查欄位原字串依序出現在 PDF 文字層（§1-11）。"""

    def __init__(self, pdf):
        self.tokens = [clean(w["text"]) for page in pdf.pages for line in page_lines(page) for w in line]
        self.tokens = [t for t in self.tokens if t]

    def find(self, text, start):
        position, first = start, None
        for token in text.split():
            while position < len(self.tokens) and self.tokens[position] != token:
                position += 1
            if position >= len(self.tokens):
                return None
            first = position if first is None else first
            position += 1
        return first


# ---------- PTR ----------

def ptr_columns(words):
    lower = [clean(w["text"]).lower() for w in words]
    needed = ("owner", "asset", "transaction", "notification", "amount")
    if not all(name in lower for name in needed):
        return None
    x = {name: words[lower.index(name)]["x0"] for name in needed}
    after_tx = [w for w in words if clean(w["text"]).lower() == "date" and w["x0"] > x["transaction"]]
    caps = [w for w in words if clean(w["text"]).lower() == "cap."]
    x["date"] = after_tx[0]["x0"] if after_tx else None
    x["cap"] = caps[0]["x0"] if caps else None
    return x if x["date"] else None


def ptr_row_start(words, cols):
    dates = [w for w in words if DATE_RE.match(w["text"])]
    near = lambda col: any(abs(w["x0"] - cols[col]) <= DATE_COLUMN_TOLERANCE for w in dates)
    return near("date") and near("notification")


def new_ptr_row(words, cols):
    dates = [w["text"] for w in words if DATE_RE.match(w["text"])]
    return {
        "owner": column_text(words, cols["owner"], cols["asset"]),
        "asset": [column_text(words, cols["asset"], cols["transaction"])],
        "tx_type_raw": column_text(words, cols["transaction"], cols["date"]),
        "tx_date_raw": dates[0], "notified_raw": dates[1] if len(dates) > 1 else None,
        "amount": [column_text(words, cols["amount"], cols["cap"])],
        "markers": [], "status_seen": False,
    }


def count_fs_markers(pdf):
    """整份文字層的 FILING STATUS 標記行數；與 parse_ptr 的表格範圍判斷完全無關（§1-11 獨立計數）。"""
    return sum(1 for page in pdf.pages for words in page_lines(page)
               if (found := marker(words)) and found[0] == "FS")


def parse_ptr(pdf):
    rows, cols, done = [], None, False
    for page in pdf.pages:
        for words in page_lines(page):
            if done:
                break
            text = line_text(words)
            header = ptr_columns(words)
            if header:
                cols = header
                continue
            if cols is None or text.startswith("Filing ID #"):
                continue
            if text.startswith("*") or is_heading(words):
                done = bool(rows)
                continue
            found = marker(words)
            if found and found[0]:
                if rows:
                    rows[-1]["markers"].append(list(found))
                    rows[-1]["status_seen"] |= found[0] == "FS"
                continue
            if all(is_bold(w) for w in words):
                continue
            if ptr_row_start(words, cols):
                rows.append(new_ptr_row(words, cols))
            elif rows and not rows[-1]["status_seen"] and not rows[-1]["markers"]:
                rows[-1]["asset"].append(column_text(words, cols["asset"], cols["transaction"]))
                rows[-1]["amount"].append(column_text(words, cols["amount"], cols["cap"]))
            elif rows and rows[-1]["markers"]:
                rows[-1]["markers"][-1][1] += " " + text
    return rows


def finish_ptr_row(row, ranges, reasons, number):
    asset_name = " ".join(p for p in row["asset"] if p)
    amount_label = " ".join(p for p in row["amount"] if p)
    ticker, code = asset_parts(asset_name)
    bounds = ranges.lookup(amount_label)
    tx_type = TX_TYPES.get(row["tx_type_raw"])
    descriptions = [value.strip() for key, value in row["markers"] if key == "D"]
    if bounds is None:
        reasons.append(f"第 {number} 列未知金額標籤：{amount_label!r}")
    if tx_type is None:
        reasons.append(f"第 {number} 列未知交易類型：{row['tx_type_raw']!r}")
    out = {
        "owner": owner_value(row["owner"], reasons, number), "asset_name": asset_name,
        "ticker": ticker, "asset_type_code": code,
        "tx_type": tx_type, "tx_date": iso_date(row["tx_date_raw"]),
        "notified_date": iso_date(row["notified_raw"]), "amount_label": amount_label,
        "amount_min": bounds[0] if bounds else None, "amount_max": bounds[1] if bounds else None,
        "description": " ".join(descriptions) or None,
    }
    if not out["tx_date"] or not out["notified_date"]:
        reasons.append(f"第 {number} 列日期不全")
    return out


# ---------- 年報 Schedule A ----------

def schedule_letter(words):
    if len(words) < 2 or not is_heading(words):
        return None
    first, second = words[0]["text"], clean(words[1]["text"])
    is_schedule = ("\x00" in first and first[0] == "S") or clean(first).lower() == "schedule"
    match = re.match(r"^([A-Z]):", second)
    return match.group(1) if is_schedule and match else None


def annual_columns(words):
    lower = [clean(w["text"]).lower() for w in words]
    if not ("asset" in lower and "owner" in lower and "value" in lower and "income" in lower):
        return None
    return {
        "asset": words[lower.index("asset")]["x0"], "owner": words[lower.index("owner")]["x0"],
        "value": words[lower.index("value")]["x0"], "income": words[lower.index("income")]["x0"],
    }


def value_incomplete(label):
    return label.endswith("-") or label.endswith("Over") or ("(" in label and ")" not in label)


def schedule_a_markers(pdf):
    """Schedule A 標題到下一個 Schedule 標題之間「全部行」的 [XX] 代碼數，不依賴欄位表頭（§1-11 獨立計數）。
    回傳 (是否找到 Schedule A, 代碼數, 下一個 Schedule 字母或 None＝直到文件結束)。"""
    seen_a, count, letter = False, 0, None
    for page in pdf.pages:
        for words in page_lines(page):
            found_letter = schedule_letter(words)
            if found_letter:
                if letter == "A":
                    return seen_a, count, found_letter
                letter = found_letter
                seen_a |= letter == "A"
                continue
            if letter == "A":
                count += sum(1 for w in words if TYPE_CODE_TOKEN_RE.search(clean(w["text"])))
    return seen_a, count, None


def parse_annual(pdf):
    rows, cols, letter = [], None, None
    for page in pdf.pages:
        for words in page_lines(page):
            found_letter = schedule_letter(words)
            if found_letter:
                letter = found_letter
                continue
            if letter != "A":
                continue
            header = annual_columns(words)
            if header:
                cols = header
                continue
            text = line_text(words)
            if cols is None or text.startswith("Filing ID #") or text.startswith("*"):
                continue
            found = marker(words)
            if found and found[0]:
                if rows:
                    rows[-1]["markers"].append(list(found))
                continue
            if all(is_bold(w) for w in words):
                continue
            asset_part = column_text(words, cols["asset"], cols["owner"])
            value_part = column_text(words, cols["value"], cols["income"])
            current = rows[-1] if rows else None
            starts_value = bool(VALUE_START_RE.match(value_part)) and bool(asset_part)
            if starts_value and (current is None or not value_incomplete(" ".join(current["value"]))):
                rows.append({"asset": [asset_part], "owner": column_text(words, cols["owner"], cols["value"]),
                             "value": [value_part], "markers": []})
            elif current and current["markers"]:
                current["markers"][-1][1] += " " + text
            elif current:
                current["asset"].append(asset_part)
                current["value"].append(value_part)
    return rows


def finish_annual_row(row, ranges, reasons, number):
    asset_name = " ".join(p for p in row["asset"] if p)
    value_label = " ".join(p for p in row["value"] if p)
    ticker, code = asset_parts(asset_name)
    bounds = ranges.lookup(value_label)
    if bounds is None:
        reasons.append(f"第 {number} 列未知金額標籤：{value_label!r}")
    return {
        "owner": owner_value(row["owner"], reasons, number), "asset_name": asset_name, "ticker": ticker,
        "asset_type": code, "value_label": value_label,
        "value_min": bounds[0] if bounds else None, "value_max": bounds[1] if bounds else None,
    }


# ---------- 主流程 ----------

def self_check(rows, label_key, stream, reasons):
    cursor = 0
    for number, row in enumerate(rows, start=1):
        position = stream.find(row["asset_name"], cursor)
        if not row["asset_name"] or position is None:
            reasons.append(f"第 {number} 列 asset_name 不在文字層：{row['asset_name']!r}")
            continue
        cursor = position
        if not row[label_key] or stream.find(row[label_key], cursor) is None:
            reasons.append(f"第 {number} 列 {label_key} 不在文字層：{row[label_key]!r}")


def check_schedule_range(seen_a, next_letter, reasons):
    """Schedule A 之後必須緊接 Schedule B；否則代表標題漏判或範圍提早切換。"""
    if not seen_a:
        reasons.append("找不到 Schedule A 標題")
    elif next_letter != "B":
        reasons.append(f"Schedule A 之後不是 Schedule B（實際：{next_letter or '直到文件結束'}）")


def parse(pdf_path, kind, ranges):
    with pdfplumber.open(pdf_path) as pdf:
        text_chars = sum(len(clean(page.extract_text() or "").strip()) for page in pdf.pages)
        if text_chars < MIN_TEXT_CHARS:
            return {"status": "needs_review", "reasons": [f"文字層幾乎為空（{text_chars} 字），疑為掃描檔"],
                    "marker_count": 0, "rows": []}
        reasons = []
        if kind == "ptr":
            marker_count = count_fs_markers(pdf)
            rows = [finish_ptr_row(r, ranges, reasons, i) for i, r in enumerate(parse_ptr(pdf), start=1)]
            label_key, marker_name = "amount_label", "FILING STATUS"
        else:
            seen_a, marker_count, next_letter = schedule_a_markers(pdf)
            check_schedule_range(seen_a, next_letter, reasons)
            rows = [finish_annual_row(r, ranges, reasons, i) for i, r in enumerate(parse_annual(pdf), start=1)]
            label_key, marker_name = "value_label", "資產類型代碼 [XX]"
        if not rows:
            reasons.append("找不到任何資料列")
        if len(rows) != marker_count:
            reasons.append(f"列數 {len(rows)} ≠ {marker_name} 標記數 {marker_count}")
        self_check(rows, label_key, TokenStream(pdf), reasons)
    return {"status": "needs_review" if reasons else "parsed", "reasons": reasons,
            "marker_count": marker_count, "rows": rows}


def main(argv=None):
    parser = argparse.ArgumentParser(description="House PTR／年報 PDF 解析")
    parser.add_argument("--kind", choices=["ptr", "annual"], required=True)
    parser.add_argument("--ranges", required=True)
    parser.add_argument("pdf")
    args = parser.parse_args(argv)
    result = parse(args.pdf, args.kind, Ranges(args.ranges))
    json.dump(result, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
