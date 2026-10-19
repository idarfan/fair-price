"""OGE Form 278e 年報解析（hall-of-fame-spec Q2）— 只做 PDF → JSON，不碰資料庫。

用法：oge_parser.py --ranges config/hall_of_fame_ranges.yml <pdf>
輸出：{"status", "reasons", "marker_count", "textlayer": {"ratio", "usable"}, "rows": [...]}

版面（2026-10-19 實測 Integrity.gov iText、Acrobat、Acrobat Paper Capture 三類）：
- 每頁表格有水平框線；以框線切出的橫條為一列。描述可在金額的上方或下方換行，不能以「編號那一行」分列。
- 欄位：# ／ Description ／（Schedule 才有 Underlying Assets and Location）／ EIF ／ Value ／ Income…（／ Ownership %）。
  欄位邊界每頁由表頭重算。
- Part 標題：「Part 6: Other Assets and Income」或「6. Other Assets and Income」；附件頁首也有「Part 2: …」。
使用者裁示（2026-10-19）：收 Part 2（self）、Part 5（SP）、Part 6（self，OGE 不區分本人／配偶／子女）；
沒有金額的容器列不寫入，名稱以「 › 」併到子列 asset_name 前。
"""
import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))  # -I 隔離模式不含腳本目錄
from house_parser import TICKER_RE, Ranges, clean  # noqa: E402

import pdfplumber  # noqa: E402

ASSET_PARTS = {2: "self", 5: "SP", 6: "self"}
PART_TITLES = ("Filer's Positions", "Filer's Employment Assets", "Filer's Employment Agreements", "Filer's Sources",
               "Spouse's Employment Assets", "Other Assets and Income", "Transactions", "Liabilities", "Gifts and Travel")
PART_RE = re.compile(r"^(?:Part\s+)?([1-9])[.:]\s+(.+)$", re.I)
NUMBER_RE = re.compile(r"^(\d+(?:\.\d+)*)\.?$")
VALUE_RE = re.compile(
    r"None \(or less than \$1,001\)|Spouse/DC Over \$1,000,000|Over \$[\d,]+|Value not readily ascertainable"
    r"|None \(or less than [\d,]+\s*(?:Euro|EURO|EUR|GBP)\)"
    r"|[\d,]+(?:\.\d+)?(?:\s*to\s*[\d,]+(?:\.\d+)?)?\s*(?:Euro|EURO|EUR|GBP)\b"  # 外幣照原字串，查表失敗 → needs_review
    r"|\$[\d,]+(?:\.\d{2})?\s*(?:-|to)\s*\$[\d,]+|\$[\d,]+(?:\.\d{2})?", re.I)
NOT_ASCERTAINABLE = "Value not readily ascertainable"
RULE_MIN_WIDTH = 150
HEADER_SPAN = 8
MISSING_INCOME_WIDTH = 110
LINE_TOLERANCE = 2.5
TEXTLAYER_MIN_RATIO = 0.95
CLEAN_TOKEN_RE = re.compile(r"[A-Za-z0-9$&.,'()/#%:;\-\[\]\"+*@!?–’]+")
SEPARATOR = " › "


# ---------- 文字層判定（規格 Q2：可讀英文字比例 ≥ 95%）----------

def textlayer(tokens):
    """tokens：全文件含英文字母的 token。"""
    good = sum(1 for t in tokens if CLEAN_TOKEN_RE.fullmatch(t))
    ratio = good / len(tokens) if tokens else 0.0
    return {"ratio": round(ratio, 4), "usable": bool(tokens) and ratio >= TEXTLAYER_MIN_RATIO}


# ---------- 版面工具 ----------

def lines_of(words):
    lines = []
    for w in sorted(words, key=lambda w: (w["top"], w["x0"])):
        if lines and abs(lines[-1][0]["top"] - w["top"]) <= LINE_TOLERANCE:
            lines[-1].append(w)
        else:
            lines.append([w])
    return [sorted(line, key=lambda w: w["x0"]) for line in lines]


def text_of(words):
    return clean(" ".join(w["text"] for w in words))


def part_header(line):
    match = PART_RE.match(text_of(line))
    if match and match.group(2).startswith(PART_TITLES):
        return int(match.group(1))
    return None


def table_header(line):
    """表頭列：同一行同時有 Description 與 Value。回傳欄位起點 {名稱: x0}。"""
    cols = {}
    for w in line:
        key = clean(w["text"]).lower()
        if key in ("#", "description", "underlying", "eif", "value", "income", "ownership") and key not in cols:
            cols[key] = w["x0"]
    return cols if "description" in cols and "value" in cols else None


def rules(page):
    ys = [l["top"] for l in page.lines if abs(l["top"] - l["bottom"]) < 1 and l["x1"] - l["x0"] > RULE_MIN_WIDTH]
    ys += [r["top"] for r in page.rects if r["height"] < 2 and r["width"] > RULE_MIN_WIDTH]
    merged = []
    for y in sorted(ys):
        if not merged or y - merged[-1] > 2:
            merged.append(y)
    return merged


def column_bounds(cols):
    """# 欄在 Description 左側；Description 到下一欄（Underlying／EIF）；Value 到 Income（沒有就到頁尾）。"""
    desc_end = min(x for k, x in cols.items() if k in ("underlying", "eif") and x > cols["description"]) \
        if any(k in cols for k in ("underlying", "eif")) else cols["value"]
    # 抓不到 Income 欄時不可放到頁尾（會把所得金額當資產價值）：限寬並由 page_rows 記原因。
    value_end = cols.get("income", cols["value"] + MISSING_INCOME_WIDTH)
    underlying = (cols["underlying"] - 2, cols.get("eif", cols["value"]) - 2) if "underlying" in cols else (0, 0)
    # Value 欄左界：EIF 與 Value 表頭的中點（太寬會吃進 EIF 欄的 N/A／No）
    value_start = (cols["eif"] + cols["value"]) / 2 if "eif" in cols and cols["eif"] < cols["value"] else cols["value"] - 30
    return {"number": (0, cols["description"] - 2), "description": (cols["description"] - 4, desc_end - 2),
            "underlying": underlying, "missing_income": "income" not in cols,
            "value": (value_start, value_end - 2), "income": (value_end - 2, cols.get("ownership", float("inf")))}


def in_bounds(word, bounds):
    return bounds[0] <= word["x0"] < bounds[1]


# Paper Capture（Acrobat OCR）會把編號的 1 認成 I／l、0 認成 O。
OCR_DIGITS = str.maketrans({"I": "1", "l": "1", "O": "0"})
WRAP_GAP = 4  # 長編號（14.1.7.1）在窄欄換行時，上下兩段的間距


FRAGMENT_RE = re.compile(r"^\.\d+(?:\.\d+)*\.?$")


def number_token(word):
    text = clean(word["text"])
    if re.fullmatch(r"[0-9IlO.]+", text) and re.search(r"[0-9.]", text):
        text = re.sub(r"\.{2,}", ".", text.translate(OCR_DIGITS))  # Trump 附件有「115..6」
    return text if NUMBER_RE.match(text) or FRAGMENT_RE.match(text) else None


def number_groups(words):
    """# 欄字詞依上下順序合併窄欄換行的長編號：「14.1.7.」＋「1」、「14.1.23」＋「.1」。
    下一段若自己帶尾點（Vance 每個編號都是「4.5.」）就是新的一列，不接。
    同一行的字詞先接起來：Paper Capture 會把「11.」拆成「I」「I.」兩個字詞（Vance 2026 第 5 頁）。"""
    groups = []
    for line in lines_of(words):
        token = number_token({"text": "".join(clean(w["text"]) for w in line)})
        if token is None:
            continue
        top, bottom = line[0]["top"], max(w["bottom"] for w in line)
        close = groups and top - groups[-1][1] < WRAP_GAP
        if close and (token.startswith(".") or (groups[-1][0].endswith(".") and not token.endswith("."))):
            groups[-1] = (groups[-1][0] + token, bottom)
        elif not token.startswith("."):
            groups.append((token, bottom))
    return [g[0].rstrip(".") + ("." if g[0].endswith(".") else "") for g in groups if NUMBER_RE.match(g[0])]


# ---------- 逐頁走訪：Part、表頭、橫條 ----------

CHUNK_PAGES = 100


def pages_of(pdf_path):
    """逐頁產生 (頁碼, page)。每 CHUNK_PAGES 頁重開一次 PDF：pdfminer 會把已解析頁面的資源留到檔案關閉，
    Trump 2026（927 頁）一次開完要 3.7GB 記憶體。"""
    with pdfplumber.open(pdf_path) as pdf:
        total = len(pdf.pages)
    for start in range(0, total, CHUNK_PAGES):
        numbers = list(range(start + 1, min(start + CHUNK_PAGES, total) + 1))
        with pdfplumber.open(pdf_path, pages=numbers) as pdf:
            for number, page in zip(numbers, pdf.pages):
                yield number, page
                page.flush_cache()


def walk(pdf_path):
    """產生 (頁碼, page, 字詞, 區段)；Part 跨頁沿用，表頭每頁重抓。"""
    part = None
    for number, page in pages_of(pdf_path):
        words = page.extract_words(x_tolerance=1.5, keep_blank_chars=False)
        lines = lines_of(words)
        segments, bounds, header_bottom = [], None, None
        for line in lines:
            header = part_header(line)
            if header is not None:
                # Part 標題也是區段分界（沒有欄位）：標題以下、下一個表頭以上的字不屬於任何資產表格。
                part, bounds = header, None
                segments.append((part, None, min(w["top"] for w in line) - 0.5))
                continue
            if table_header(line):
                # Paper Capture 的表頭字縱座標會差幾點（Vance 2026 第 5 頁的 Income Type／Amount 落在下一行），
                # 所以連同上下 HEADER_SPAN 內的字一起認欄位（Q2 r1 問題 2）。
                near = [w for w in words if abs(w["top"] - line[0]["top"]) <= HEADER_SPAN]
                header_words = sorted(near, key=lambda w: w["x0"])
                bounds = column_bounds(table_header(header_words))
                header_bottom = max(w["bottom"] for w in header_words)
                segments.append((part, bounds, header_bottom))
        yield number, page, words, segments


def segment_for(word, segments):
    """字詞所屬的表格區段：最後一個表頭在它上方者。"""
    found = None
    for part, bounds, header_bottom in segments:
        if word["top"] > header_bottom:
            found = (part, bounds, header_bottom)
    return found


def page_markers(words, segments):
    """自洽檢查用的標記數：不經框線切列，直接數 Part 2／5／6 表格內 # 欄的編號字詞。"""
    column = [w for w in words if (seg := segment_for(w, segments)) and seg[0] in ASSET_PARTS and seg[1]
              and in_bounds(w, seg[1]["number"])]
    return len(number_groups(column))


def page_rows(number, page, words, segments, reasons):
    asset_segments = [s for s in segments if s[0] in ASSET_PARTS and s[1]]
    if not asset_segments:
        return []
    if any(s[1]["missing_income"] for s in asset_segments):
        reasons.append(f"第 {number} 頁表頭缺 Income 欄，Value 欄右界無法確定")
    ys = rules(page)
    if len(ys) < 2:
        reasons.append(f"第 {number} 頁找不到表格框線")
        return []
    rows, edges = [], [0.0, *ys, float(page.height)]
    for top, bottom in zip(edges, edges[1:]):
        band = [w for w in words if top <= (w["top"] + w["bottom"]) / 2 < bottom]
        row = band_row(band, segments, number, reasons)
        if row:
            rows.append(row)
    return rows


def scan(pdf_path, reasons):
    """單趟走訪：每頁只解析一次，同時取文字層 token、編號標記數、資料列與自洽檢查用的頁面文字。"""
    tokens, marker_count, rows, page_text = [], 0, [], {}
    for number, page, words, segments in walk(pdf_path):
        text = page.extract_text() or ""
        tokens += [t for t in text.split() if re.search(r"[A-Za-z]", t)]
        marker_count += page_markers(words, segments)
        found = page_rows(number, page, words, segments, reasons)
        if found:
            page_text[number] = squash(text)
            rows += found
    return tokens, marker_count, rows, page_text


def band_row(band, segments, page_number, reasons):
    if not band:
        return None
    # 以橫條內字詞頂端的中位數判斷所屬區段：表頭收上下 HEADER_SPAN 的字後，表頭下緣可能壓到第一列最上方的字
    tops = sorted(w["top"] for w in band)
    seg = segment_for({"top": tops[len(tops) // 2]}, segments)
    if not seg or seg[0] not in ASSET_PARTS or seg[1] is None:
        return None
    part, bounds, _ = seg
    numbers = number_groups([w for w in band if in_bounds(w, bounds["number"])])
    description = text_of(drop_endnotes(lines_of([w for w in band if in_bounds(w, bounds["description"])])))
    value_text = normalize_value(
        text_of([w for line in lines_of([w for w in band if in_bounds(w, bounds["value"])]) for w in line]))
    income_text = text_of([w for line in lines_of([w for w in band if in_bounds(w, bounds["income"])]) for w in line])
    underlying_text = text_of([w for line in lines_of([w for w in band if in_bounds(w, bounds["underlying"])]) for w in line])
    label, recognized = value_label(value_text)
    if not numbers:
        if not VALUE_RE.search(value_text):
            return None  # 換頁重複的帳戶標題、頁尾說明文字等：沒有編號、Value 欄也沒有金額格式
        # 有金額但編號是 OCR 亂碼（Vance 2026 Narya Capital Fund I）：照列寫入、不加容器前綴，記原因（使用者裁示）
        reasons.append(f"第 {page_number} 頁有金額但沒有編號的列（已照列寫入）：{description!r}")
    if len(numbers) > 1:
        reasons.append(f"第 {page_number} 頁一個橫條內有多個編號：{numbers}")
    return {"page": page_number, "part": part, "number": NUMBER_RE.match(numbers[0]).group(1) if numbers else ORPHAN,
            "description": description, "value_label": label, "value_recognized": recognized,
            "value_text": value_text, "income_text": income_text, "underlying_text": underlying_text,
            "band_text": text_of(sorted(band, key=lambda w: (w["top"], w["x0"])))}


ORPHAN = "?"
ENDNOTE = ("See", "Endnote")


def drop_endnotes(lines):
    """Integrity.gov 在 Description 與 EIF 之間有一欄沒有表頭的「See Endnote」，不屬於描述（Q2 r1 問題 3）。"""
    kept = []
    for line in lines:
        skip = set()
        for i in range(len(line) - 1):
            if (clean(line[i]["text"]), clean(line[i + 1]["text"])) == ENDNOTE:
                skip.update((i, i + 1))
        kept += [w for i, w in enumerate(line) if i not in skip]
    return kept


def normalize_value(text):
    """Value 儲存格的 OCR／打字雜訊：「$1 ,000」「( or」「$500,001 to 1,000,000」（第二段漏 $）。"""
    text = re.sub(r"(\d)\s+,(\d)", r"\1,\2", text)
    text = re.sub(r"\$\s+(\d)", r"$\1", text)
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"(\$[\d,]+\s+to\s+)(?=\d)", r"\1$", text)
    return re.sub(r"\s+", " ", text).strip()


def value_label(cell):
    """回傳 (value_label, 是否完整辨識)。金額必須從儲存格開頭起算；其後只允許不含數字與 $ 的文字
    （Trump Part 6 表頭沒有 Income Type，DIVIDEND／INTEREST 會落在 Value 欄）。其餘一律視為無法辨識，
    value_label 存儲存格原字串，由 finish 記原因（Q2 r1 問題 1：不得把截斷的區間當成精確金額）。"""
    if not cell:
        return None, True
    match = VALUE_RE.match(cell)
    rest = cell[match.end():].strip() if match else ""
    # 「$500,001 to」這類截斷的區間：其後以 to／- 開頭，不可當成精確金額
    if match and not re.search(r"[\d$]", rest) and not re.match(r"(?:to|-)(?:\s|$)", rest, re.I):
        return match.group(0), True
    return cell, False


# ---------- 容器列與欄位整理 ----------

def depth(number):
    return number.count(".")


def assign_names(rows):
    """階層編號（8 → 8.1）以祖先描述為前綴；平編號區段（編號重新從小開始）若第一列沒有金額、
    下一列也是頂層，視為該區段的帳戶標題（Trump「INVESTMENT ACCOUNT #1」），套用到整段頂層列。"""
    named, by_number, section_title, last_top = [], {}, None, None
    # 平編號帳戶的特徵：同一 Part 內頂層編號會重新從 1 開始（Trump 多個 INVESTMENT ACCOUNT）。
    # 沒有這個特徵的 Part（Burgum Part 2 第 1 列「State of North Dakota」是薪資列）不套用帳戶標題。
    restarts = {part for part in {r["part"] for r in rows}
                if sum(1 for r in rows if r["part"] == part and r["number"] in ("1", "1.")) > 1}
    for i, row in enumerate(rows):
        if row["number"] == ORPHAN:
            named.append({**row, "asset_name": row["description"]})
            continue
        key = (row["part"], row["number"])
        top = int(row["number"].split(".")[0])
        if depth(row["number"]) == 0:
            if last_top is None or top <= last_top or row["part"] != rows[i - 1]["part"]:
                nxt = rows[i + 1] if i + 1 < len(rows) else None
                is_title = (row["part"] in restarts and row["value_label"] is None and not row["income_text"]
                            and not POINTER_RE.search(row["band_text"])
                            and nxt is not None and nxt["part"] == row["part"] and depth(nxt["number"]) == 0)
                section_title = row["description"] if is_title else None
                if is_title:
                    named.append({**row, "asset_name": row["description"], "section_title": True})
                    by_number[key] = row["description"]
                    last_top = top
                    continue
            last_top = top
        parents = [by_number.get((row["part"], ".".join(row["number"].split(".")[:n])))
                   for n in range(1, depth(row["number"]) + 1)]
        prefix = [section_title] if section_title and row["description"] != section_title else []
        prefix += [p for p in parents if p]
        by_number[key] = row["description"]
        named.append({**row, "asset_name": SEPARATOR.join([*prefix, row["description"]])})
    return named


POINTER_RE = re.compile(r"\bSee (?:Lines?|Attached)\b|Intentionally Left Blank", re.I)
NOT_ASCERTAINABLE_RE = re.compile(r"not readily\s+ascertainable", re.I)
INACTIVE_RE = re.compile(r"\bInactive\b", re.I)


def context(row):
    """判斷「不可估值」的文字範圍：描述、Underlying Assets（Trump 附件）、Value 欄。"""
    return f"{row['description']} {row['underlying_text']} {row['value_text']}"


def classify(rows, reasons):
    """沒有金額的列：有子列 → 容器（不寫入）；「See Line／See Attached」→ 指向別列（不寫入）；
    其餘葉節點照列：描述寫明不可估值者標 Value not readily ascertainable，否則記原因（§1-5 不得靜默丟棄）。"""
    parents = {(r["part"], ".".join(r["number"].split(".")[:n])) for r in rows for n in range(1, depth(r["number"]) + 1)}
    valued = {(r["part"], r["number"]) for r in rows if r["value_label"] is not None}
    kept, skipped = [], 0
    for r in rows:
        ancestors = {(r["part"], ".".join(r["number"].split(".")[:n])) for n in range(1, depth(r["number"]) + 1)}
        if r["value_label"] is not None:
            kept.append(r)
        elif not r["description"] and not r["value_text"] and not r["income_text"]:
            skipped += 1  # 表單預先印好的空白編號列（Trump Part 2 的 2.～17.）
        elif (r["part"], r["number"]) in parents or r.get("section_title") or POINTER_RE.search(r["band_text"]):
            skipped += 1
        elif ancestors & valued:
            skipped += 1  # 有金額的基金底下逐一揭露的投資標的（Lutnick 9.5.x、Bessent 前 5 大持股），金額已含在上層
        elif r["income_text"] and not r["value_text"] and not NOT_ASCERTAINABLE_RE.search(context(r)):
            skipped += 1  # Part 2 的薪資／顧問費／預付款等純所得列：沒有資產價值，不是持股
        elif INACTIVE_RE.search(f"{r['description']} {r['underlying_text']}") and not r["value_text"]:
            skipped += 1  # 已停業、未申報價值的實體（Trump Marks Holdings LP）
        elif NOT_ASCERTAINABLE_RE.search(context(r)):
            kept.append({**r, "value_label": NOT_ASCERTAINABLE})
        else:
            reasons.append(f"第 {r['page']} 頁 #{r['number']} 沒有金額也不是容器：{r['description']!r}")
            kept.append(r)
    return kept, skipped


def finish(row, ranges, reasons):
    label = row["value_label"]
    out = {"owner": ASSET_PARTS[row["part"]], "asset_name": row["asset_name"], "ticker": None, "asset_type": None,
           "value_label": label, "value_min": None, "value_max": None,
           "page": row["page"], "part": row["part"], "number": row["number"]}
    tickers = TICKER_RE.findall(row["description"])
    out["ticker"] = tickers[-1] if tickers else None
    if not row.get("value_recognized", True):
        reasons.append(f"第 {row['page']} 頁 #{row['number']} Value 欄無法完整辨識：{label!r}")
        return out
    if label is None or label.lower() == NOT_ASCERTAINABLE.lower():
        return out  # 不可估值：照列、不入佔比（規格 Q2），不是解析問題
    amounts = ranges.lookup(re.sub(r"\s+to\s+", " - ", label))
    if amounts is None:
        reasons.append(f"第 {row['page']} 頁 #{row['number']} 未知金額標籤：{label!r}")
    else:
        out["value_min"], out["value_max"] = amounts
    return out


def self_check(rows, page_text, reasons):
    """§1-11：描述與金額原字串的每個 token 都要出現在該列所在頁的文字層。
    以 token 為單位、在去空白的頁面文字中找子字串：儲存格換行時其他欄位會插在中間，整串比對不到；
    Paper Capture 又常把「$1,001 -」黏成一個 token，逐 token 精確比對也不行。"""
    for row in rows:
        text = page_text[row["page"]]
        for field in ("description", "value_label"):
            # 去掉開頭的 $：normalize_value 會替「$500,001 to 1,000,000」的第二段補上原文沒有的 $
            missing = [t for t in (row[field] or "").split() if squash(t).lstrip("$") not in text]
            if missing:
                reasons.append(f"第 {row['page']} 頁 #{row['number']} {field} 不在文字層：{missing[:3]}")


def squash(text):
    return re.sub(r"\s+", "", clean(text))


def parse(pdf_path, ranges):
    reasons = []
    tokens, marker_count, raw, page_text = scan(pdf_path, reasons)
    layer = textlayer(tokens)
    if not layer["usable"]:
        return {"status": "needs_review", "reasons": [f"文字層不可用（可讀比例 {layer['ratio']:.2%}），待 Q3 OCR"],
                "marker_count": 0, "container_count": 0, "textlayer": layer, "rows": []}
    self_check(raw, page_text, reasons)
    if not raw:
        reasons.append("找不到任何 Part 2／5／6 資料列")
    numbered = sum(1 for r in raw if r["number"] != ORPHAN)  # 編號亂碼照列寫入的列本來就沒有標記，另有原因
    if numbered != marker_count:
        reasons.append(f"列數 {numbered} ≠ 編號標記數 {marker_count}")
    kept, skipped = classify(assign_names(raw), reasons)
    rows = [finish(r, ranges, reasons) for r in kept]
    return {"status": "needs_review" if reasons else "parsed", "reasons": reasons, "marker_count": marker_count,
            "container_count": skipped, "textlayer": layer, "rows": rows}


def main(argv=None):
    parser = argparse.ArgumentParser(description="OGE Form 278e 年報解析")
    parser.add_argument("--ranges", required=True)
    parser.add_argument("pdf")
    args = parser.parse_args(argv)
    json.dump(parse(args.pdf, Ranges(args.ranges)), sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
