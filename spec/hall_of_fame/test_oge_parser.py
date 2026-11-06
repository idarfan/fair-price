"""oge_parser.py 的 pytest（規格 Q2）。執行：lib/hall_of_fame/venv/bin/python -m pytest spec/hall_of_fame

真實 PDF 夾具只放小檔（Bessent 2026／2025、Vance 2025 抽 3 頁）；Trump 的特殊版面（平編號帳戶、歐元、
「115..6」、空白樣板列、See lines、Inactive、純所得列）每頁內嵌約 860KB 字型，改以合成資料測各函式，
正式庫全份解析結果見 Q2 送審檔。"""
import pathlib
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib" / "hall_of_fame"))

import oge_parser  # noqa: E402
from house_parser import Ranges  # noqa: E402

FIXTURES = ROOT / "spec" / "fixtures" / "hall_of_fame" / "oge"
RANGES = Ranges(ROOT / "config" / "hall_of_fame_ranges.yml")


def parse(name):
    return oge_parser.parse(str(FIXTURES / name), RANGES)


def by_number(result):
    return {(r["part"], r["number"]): r for r in result["rows"]}


def word(text, x0, top):
    return {"text": text, "x0": x0, "x1": x0 + 4 * len(text), "top": top, "bottom": top + 8}


def row(number, description="", value=None, part=6, **extra):
    base = {"page": 1, "part": part, "number": number, "description": description, "value_label": value,
            "value_text": value or "", "income_text": "", "underlying_text": "", "band_text": description}
    return {**base, **extra}


# ---------- 真實 PDF ----------

def test_bessent_2026_integrity_gov_report():
    result = parse("bessent_2026.pdf")
    rows = by_number(result)

    assert result["status"] == "parsed", result["reasons"]
    assert (result["marker_count"], len(result["rows"]), result["container_count"]) == (72, 58, 14)
    assert result["textlayer"]["usable"] is True
    spy = rows[(5, "1.2")]
    assert spy["owner"] == "SP" and spy["ticker"] == "SPY"
    assert spy["asset_name"] == "IRA #1 › SPDR S&P 500 ETF IV (SPY)"
    assert (spy["value_min"], spy["value_max"]) == (100001, 250000)
    bank = rows[(6, "21")]
    assert (bank["asset_name"], bank["value_label"], bank["value_min"], bank["value_max"]) == \
        ("U.S. bank #7 (cash)", "Over $50,000,000", 50000001, None)
    assert rows[(2, "2.1")]["asset_name"] == "Key Square Group LP 401(k) plan › T Rowe Price Retirement 2025 Fund I"


def test_bessent_2025_wrapped_numbers_and_fund_underlyings():
    result = parse("bessent_2025_nominee.pdf")
    rows = by_number(result)

    assert result["status"] == "parsed", result["reasons"]
    assert result["marker_count"] == len(result["rows"]) + result["container_count"]
    # 「14.1.23」／「.1」換行接回 14.1.23.1，上層 Key Square Partners II, LP 成為容器前綴
    assert rows[(6, "14.1.23.1")]["asset_name"].endswith("Key Square Partners II, LP › SPDR S&P 500 ETF Trust (SPY)")
    # 有金額的基金底下揭露的前 5 大持股（14.1.7.1～5）不另列
    assert not any(number.startswith("14.1.7.") for _part, number in rows)
    assert (6, "14.1.7") in rows


def test_vance_paper_capture_not_ascertainable_and_typo():
    result = parse("vance_2025_subset.pdf")
    rows = by_number(result)

    assert result["status"] == "needs_review"
    assert result["reasons"] == ["第 3 頁 #4.5 未知金額標籤：'$250,000 - $500,000'"]
    carried = rows[(2, "4.5.1")]
    assert carried["value_label"] == oge_parser.NOT_ASCERTAINABLE
    assert (carried["value_min"], carried["value_max"]) == (None, None)
    assert carried["asset_name"].startswith("JD Vance Enterprises LLC › Narya Capital, GP I, LLC")


# ---------- 文字層判定 ----------

@pytest.mark.parametrize("tokens, usable", [
    (["Description", "Value", "$1,001", "-", "$15,000"] * 20, True),
    (["Descr¡ption", "V@lue", "�YL-", "t/t2/z)-", "Over"] * 20, False),
    ([], False),
])
def test_textlayer(tokens, usable):
    assert oge_parser.textlayer(tokens)["usable"] is usable


# ---------- 編號 ----------

@pytest.mark.parametrize("words, expected", [
    ([word("14.1.7.", 20, 100), word("1", 20, 109)], ["14.1.7.1"]),        # iText 窄欄換行
    ([word("14.1.23", 20, 100), word(".1", 20, 109)], ["14.1.23.1"]),
    ([word("4.5.2.", 20, 100), word("4.5.3.", 20, 109)], ["4.5.2.", "4.5.3."]),  # Vance 尾點、列距小：不接
    ([word("I.I.", 20, 100)], ["1.1."]),                                    # Paper Capture 把 1 認成 I
    ([word("115..6", 20, 100)], ["115.6"]),                                 # Trump 附件的筆誤
    ([word("-\"'·?-·", 20, 100)], []),
])
def test_number_groups(words, expected):
    assert oge_parser.number_groups(words) == expected


# ---------- 容器名稱 ----------

def test_flat_account_sections_prefix_rows():
    rows = oge_parser.assign_names([
        row("1", "INVESTMENT ACCOUNT #1"), row("2", "ARES CAP CORP COM", "$1,001 - $15,000"),
        row("3", "VISA INC COM CL A", "$1,001 - $15,000"),
        row("1", "INVESTMENT ACCOUNT #2"), row("2", "U S TREASURY NOTE", "$15,001 - $50,000"),
    ])
    names = [r["asset_name"] for r in rows if not r.get("section_title")]
    assert names == ["INVESTMENT ACCOUNT #1 › ARES CAP CORP COM", "INVESTMENT ACCOUNT #1 › VISA INC COM CL A",
                     "INVESTMENT ACCOUNT #2 › U S TREASURY NOTE"]


def test_hierarchical_numbers_prefix_ancestors_without_section_title():
    rows = oge_parser.assign_names([
        row("1", "IRA #1", part=5), row("1.1", "SPDR S&P 500 ETF IV (SPY)", "$100,001 - $250,000", part=5),
        row("2", "IRA #2", part=5), row("2.1", "MITTX", "$50,001 - $100,000", part=5),
    ])
    assert [r["asset_name"] for r in rows] == ["IRA #1", "IRA #1 › SPDR S&P 500 ETF IV (SPY)", "IRA #2", "IRA #2 › MITTX"]


# ---------- 沒有金額的列 ----------

def test_classify_valueless_rows():
    reasons = []
    rows = [
        row("2"),                                                                  # 空白樣板列
        row("117", "Excel Venture I Corporation", band_text="117 Excel Venture I Corporation See Lines 118 and 165"),
        row("295", "Trump Marks Holdings LP", underlying_text="Inactive"),
        row("4", "Kemnay Services Limited", part=2, income_text="Consulting fee $250,000"),
        row("9.5", "RRE Ventures VIII, L.P.", "$1,000,001 - $5,000,000"),
        row("9.5.1", "Anomaly Insights, Inc."),                                    # 有金額基金底下的標的
        row("168", "SLC Turnberry Limited", underlying_text="Registered Trademark(s) (values not readily ascertainable)"),
        row("200", "Mystery LLC"),
    ]
    kept, skipped = oge_parser.classify(rows, reasons)

    assert [r["number"] for r in kept] == ["9.5", "168", "200"]
    assert kept[1]["value_label"] == oge_parser.NOT_ASCERTAINABLE
    assert skipped == 5
    assert reasons == ["第 1 頁 #200 沒有金額也不是容器：'Mystery LLC'"]


# ---------- 金額 ----------

@pytest.mark.parametrize("label, expected, reason", [
    ("$1,001 to $15,000", (1001, 15000), False),           # Trump 附件用 to
    ("None (or less than $1,001)", (0, 1000), False),
    ("Value not readily ascertainable", (None, None), False),
    ("128.63 Euro", (None, None), True),
    ("None (or less than 1,001 EURO)", (None, None), True),
    ("$15,001 to $25,000", (15001, 25000), False),         # 2026-10-19 裁示擴充（Trump 附件）
    ("Over $1,000,000", (1000001, None), False),
    ("$250,000 - $500,000", (None, None), True),           # 申報錯字維持 needs_review
])
def test_finish_value_labels(label, expected, reason):
    reasons = []
    out = oge_parser.finish({**row("1", "X", label), "asset_name": "X"}, RANGES, reasons)
    assert (out["value_min"], out["value_max"]) == expected
    assert bool(reasons) is reason


@pytest.mark.parametrize("text, label", [
    ("None (or less than 1,001 EURO)", "None (or less than 1,001 EURO)"),
    ("15,001 to 25,000 Euro", "15,001 to 25,000 Euro"),
    ("$1,001 to $15,000", "$1,001 to $15,000"),
    ("Over $50,000,000", "Over $50,000,000"),
])
def test_value_regex(text, label):
    assert oge_parser.VALUE_RE.search(text).group(0) == label


# ---------- Q2 r1 問題 1：Value 儲存格必須完整辨識 ----------

@pytest.mark.parametrize("cell, label, recognized", [
    ("$500,001 to 1,000,000", "$500,001 to $1,000,000", True),        # Trump id 5004：第二段漏 $
    ("None ( or less than $1,001)", "None (or less than $1,001)", True),  # Trump id 5055
    ("$1 ,000,001 - $5,000,000", "$1,000,001 - $5,000,000", True),     # Vance 2026 DIA：千分位前多空格
    ("$1,000,001 - $5,000,000 DIVIDEND", "$1,000,001 - $5,000,000", True),  # Trump Part 6 無 Income Type 表頭
    ("$15.00", "$15.00", True),                                      # 整格就是單一金額才是精確金額
    ("$500,001 to", "$500,001 to", False),                           # 截斷的區間
    ("$500,001 -", "$500,001 -", False),
    ("$1,000 $2,000", "$1,000 $2,000", False),
    ("154, 446", "154, 446", False),
    ("", None, True),
])
def test_value_label_requires_whole_cell(cell, label, recognized):
    assert oge_parser.value_label(oge_parser.normalize_value(cell)) == (label, recognized)


def test_unrecognized_value_is_not_written_as_an_amount():
    reasons = []
    out = oge_parser.finish({**row("5", "Trump Ice LLC", "$500,001 to", value_recognized=False), "asset_name": "Trump Ice LLC"},
                            RANGES, reasons)
    assert (out["value_min"], out["value_max"]) == (None, None)
    assert reasons == ["第 1 頁 #5 Value 欄無法完整辨識：'$500,001 to'"]


# ---------- Q2 r1 問題 2：Paper Capture 表頭 Income 欄 ----------

def test_vance_2026_page5_income_amounts_are_not_values():
    """表頭的 Income Type／Amount 被 OCR 放在下一行；舊版把 $3,000 等所得金額當成資產價值寫入。"""
    result = parse("vance_2026_p5.pdf")

    assert result["status"] == "parsed", result["reasons"]
    assert len(result["rows"]) == 9
    assert {r["value_label"] for r in result["rows"]} == {oge_parser.NOT_ASCERTAINABLE}
    assert all(r["value_min"] is None and r["value_max"] is None for r in result["rows"])


def test_missing_income_header_is_reported():
    bounds = oge_parser.column_bounds({"#": 30, "description": 60, "eif": 285, "value": 313})
    assert bounds["missing_income"] is True
    assert bounds["value"][1] == 313 + oge_parser.MISSING_INCOME_WIDTH - 2


# ---------- Q2 r1 問題 3：See Endnote 不屬於描述 ----------

def test_endnote_column_is_dropped_from_descriptions():
    result = parse("burgum_2025_nominee.pdf")
    rows = by_number(result)

    assert rows[(2, "4.2")]["asset_name"].endswith("Arthur Ventures Growth III, LP (venture capital)")
    assert not any("Endnote" in r["asset_name"] for r in result["rows"])
    assert not any("Endnote" in r["asset_name"] for r in parse("bessent_2025_nominee.pdf")["rows"])


def test_burgum_salary_row_is_not_an_account_title():
    """Part 2 第 1 列 State of North Dakota 是薪資列，不可當成平編號帳戶標題套到整個 Part。"""
    rows = by_number(parse("burgum_2025_nominee.pdf"))
    assert rows[(2, "4.1")]["asset_name"].startswith("Retirement Account #1 › ")
    assert not any(name.startswith(("State of North Dakota ›", "Line Intentionally Left Blank ›"))
                   for name in (r["asset_name"] for r in rows.values()))


def test_same_line_ocr_fragments_join_into_one_number():
    assert oge_parser.number_groups([word("I", 20, 100), word("I.", 26, 100)]) == ["11."]


def test_orphan_row_keeps_its_own_name():
    rows = oge_parser.assign_names([row("1", "IRA #1"), row(oge_parser.ORPHAN, "Narya Capital Fund I, LP", "$500,001 - $1,000,000")])
    assert rows[1]["asset_name"] == "Narya Capital Fund I, LP"


def test_marker_mismatch_needs_review(monkeypatch):
    original = oge_parser.page_markers
    monkeypatch.setattr(oge_parser, "page_markers", lambda words, segments: original(words, segments) + 1)

    result = parse("bessent_2026.pdf")

    assert result["status"] == "needs_review"
    assert any(r.startswith("列數 72 ≠ 編號標記數") for r in result["reasons"])
