"""house_parser.py 的 pytest（規格 P3）。執行：lib/hall_of_fame/venv/bin/python -m pytest spec/hall_of_fame"""
import json
import pathlib
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib" / "hall_of_fame"))

import house_parser  # noqa: E402

FIXTURES = ROOT / "spec" / "fixtures" / "hall_of_fame"
RANGES = house_parser.Ranges(ROOT / "config" / "hall_of_fame_ranges.yml")


def parse(name, kind="ptr"):
    return house_parser.parse(str(FIXTURES / name), kind, RANGES)


def test_old_format_ptr_regression():
    result = parse("20004433.pdf")

    assert result["status"] == "parsed"
    assert result["marker_count"] == 2
    first, second = result["rows"]
    assert "Treasury Bills" in first["asset_name"]
    assert first["owner"] == "self"
    assert (first["tx_type"], first["tx_date"], first["notified_date"]) == ("P", "2015-12-15", "2015-12-31")
    assert (first["amount_min"], first["amount_max"]) == (1000001, 5000000)
    assert second["owner"] == "SP"
    assert second["amount_label"] == "Spouse/DC Over $1,000,000"
    assert (second["amount_min"], second["amount_max"]) == (1000001, None)


def test_current_format_snapshot():
    snapshot = json.loads((FIXTURES / "20035553.snapshot.json").read_text(encoding="utf-8"))
    result = parse("20035553.pdf")

    assert result == snapshot
    assert result["status"] == "parsed"
    assert len(result["rows"]) == result["marker_count"]


def test_scanned_pdf_needs_review():
    result = parse("8221120.pdf")

    assert result["status"] == "needs_review"
    assert result["rows"] == []
    assert "掃描檔" in result["reasons"][0]


@pytest.mark.parametrize("label, expected", [
    ("$1,000,001 - $5,000,000", (1000001, 5000000)),
    ("Over $50,000,000", (50000001, None)),
    ("None", (0, 0)),
    ("$1 - $1,000", (1, 1000)),
    ("$15.00", (15, 15)),
    ("$15.50", (15, 16)),
    ("Undetermined", None),
    ("$1,000,001 -", None),
])
def test_ranges_lookup(label, expected):
    assert RANGES.lookup(label) == expected


@pytest.mark.parametrize("texts, expected", [
    (["F\x00\x00\x00\x00\x00", "S\x00\x00\x00\x00\x00", ":", "New"], ("FS", "New")),
    (["F", "IlINg", "S", "TaTuS:", "New"], ("FS", "New")),
    (["D\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", ":", "Purchased", "200"], ("D", "Purchased 200")),
    (["Status:", "Member"], (None, "Member")),
    (["Apple", "Inc.", "(AAPL)", "[ST]"], None),
])
def test_marker(texts, expected):
    assert house_parser.marker([{"text": t} for t in texts]) == expected


def test_count_mismatch_needs_review(monkeypatch):
    monkeypatch.setattr(house_parser, "count_fs_markers", lambda pdf: 3)

    result = parse("20004433.pdf")

    assert result["status"] == "needs_review"
    assert "列數 2 ≠ FILING STATUS 標記數 3" in result["reasons"]


def test_table_stopping_early_is_caught_by_independent_marker_count(monkeypatch):
    # 模擬表格中途遇到註腳／粗體標題而提早結束：FILING STATUS 計數不受影響，仍為 2。
    original = house_parser.parse_ptr
    monkeypatch.setattr(house_parser, "parse_ptr", lambda pdf: original(pdf)[:1])

    result = parse("20004433.pdf")

    assert result["status"] == "needs_review"
    assert result["marker_count"] == 2
    assert "列數 1 ≠ FILING STATUS 標記數 2" in result["reasons"]


def test_annual_schedule_a_counted_up_to_schedule_b():
    result = parse("10075701.pdf", kind="annual")

    assert result["marker_count"] == 68
    assert len(result["rows"]) == 68
    assert result["reasons"] == ["第 59 列未知金額標籤：'Undetermined'"]


def test_annual_rows_stopping_early_are_caught(monkeypatch):
    original = house_parser.parse_annual
    monkeypatch.setattr(house_parser, "parse_annual", lambda pdf: original(pdf)[:60])

    result = parse("10075701.pdf", kind="annual")

    assert "列數 60 ≠ 資產類型代碼 [XX] 標記數 68" in result["reasons"]


@pytest.mark.parametrize("seen_a, next_letter, expected", [
    (True, "B", []),
    (True, "C", ["Schedule A 之後不是 Schedule B（實際：C）"]),
    (True, None, ["Schedule A 之後不是 Schedule B（實際：直到文件結束）"]),
    (False, None, ["找不到 Schedule A 標題"]),
])
def test_check_schedule_range(seen_a, next_letter, expected):
    reasons = []
    house_parser.check_schedule_range(seen_a, next_letter, reasons)
    assert reasons == expected


def test_unknown_owner_needs_review():
    reasons = []
    assert house_parser.owner_value("XX", reasons, 4) == "XX"
    assert reasons == ["第 4 列未知持有人代碼：'XX'"]
