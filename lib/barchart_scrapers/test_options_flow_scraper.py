"""
options_flow_scraper 的 grid → trades 轉換測試。

2026-09-01 拿掉 CSV 下載那條路之後，逐筆交易改由 `_data[*].raw` 直接轉出。
Ruby 端（BarchartScraperService#classify_trade）依欄位名稱取值，所以這支測試
把「15 個 key 的名稱與轉換規則」釘住——欄位改名或漏轉，分類器與大單面板會
安靜地拿到 nil，不會有例外。
"""
import os
import sys
import types
import unittest
import importlib.util
from unittest.mock import AsyncMock


def _load_scraper():
    stub = types.ModuleType("cdp_helper")
    for name in ("prepare_page", "cdp_eval", "cdp_navigate", "activate_target"):
        setattr(stub, name, AsyncMock())
    sys.modules["cdp_helper"] = stub

    spec = importlib.util.spec_from_file_location(
        "options_flow_scraper",
        __file__.replace("test_options_flow_scraper.py", "options_flow_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["options_flow_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


# 取自 SONY options-flow 頁的實際 raw 列（2026-09-01 實測）
SAMPLE_ROW = {
    "symbolType": "Call",
    "side": "bid",
    "premium": 47200,
    "tradeSize": 450,
    "dte": 109,
    "delta": 0.35609264823719,
    "tradePrice": 1.05,
    "tradeCondition": "AUTO",
    "strikePrice": 27.5,
    "expiration": "2026-12-18T16:30:00-06:00",
    "volume": 451,
    "openInterest": 11488,
    "volatility": 33.282242682299,
    "label": None,
    "tradeTime": 1788183144,
}

# Ruby classify_trade 會讀的 15 個 key
EXPECTED_KEYS = {
    "option_type", "strike", "expires_at", "dte", "trade_price", "size", "side",
    "premium", "volume", "open_interest", "iv", "delta", "trade_condition",
    "open_close", "trade_time",
}


class TestGridRowsToTrades(unittest.TestCase):

    def setUp(self):
        self.trade = scraper.grid_rows_to_trades([SAMPLE_ROW])[0]

    def test_produces_exactly_the_keys_ruby_reads(self):
        self.assertEqual(set(self.trade.keys()), EXPECTED_KEYS)

    def test_direct_fields_map_through(self):
        self.assertEqual(self.trade["option_type"], "Call")
        self.assertEqual(self.trade["strike"], 27.5)
        self.assertEqual(self.trade["dte"], 109)
        self.assertEqual(self.trade["size"], 450)
        self.assertEqual(self.trade["premium"], 47200)
        self.assertEqual(self.trade["volume"], 451)
        self.assertEqual(self.trade["open_interest"], 11488)
        self.assertEqual(self.trade["trade_price"], 1.05)
        self.assertEqual(self.trade["side"], "bid")
        self.assertEqual(self.trade["expires_at"], "2026-12-18T16:30:00-06:00")

    # grid 給的是百分數（33.28 = 33.28%），DB 存小數。
    def test_iv_is_always_divided_by_100(self):
        self.assertAlmostEqual(self.trade["iv"], 0.332822, places=6)

    # 舊 CSV 的 _parse_pct 是「>1 才除以 100」，IV 0.8% 會被原樣留成 0.8。
    # 改成無條件除之後，小 IV 才算得對。
    def test_small_iv_no_longer_skips_the_division(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "volatility": 0.8}])[0]
        self.assertAlmostEqual(t["iv"], 0.008, places=6)

    def test_missing_volatility_is_none_not_zero(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "volatility": None}])[0]
        self.assertIsNone(t["iv"])

    # DB 既有 trade_time 是 "14:21:22 ET" 這種字串，格式要對齊才不會兩種混存。
    def test_trade_time_epoch_becomes_et_string(self):
        self.assertRegex(self.trade["trade_time"], r"^\d{2}:\d{2}:\d{2} ET$")

    def test_trade_time_uses_new_york_timezone(self):
        # 1788183144 = UTC 2026-08-31 13:32:24 = 09:32:24 America/New_York（EDT, UTC-4）
        self.assertEqual(self.trade["trade_time"], "09:32:24 ET")

    def test_missing_trade_time_is_none(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "tradeTime": None}])[0]
        self.assertIsNone(t["trade_time"])

    # classifier 的 AMBIGUOUS_OPEN_CLOSE 認得 "N/A"，null 會讓方向判斷走到不同分支。
    def test_null_label_becomes_na(self):
        self.assertEqual(self.trade["open_close"], "N/A")

    # 實跑 BE 時發現的：grid 的 label 是長格式 "(S) - Sell To Open"，
    # 而 classifier 是拿短格式 "SellToOpen" 做 pattern match。不正規化的話方向
    # 判斷會全部掉到 INDETERMINATE，而且完全不會報錯——單元測試當初用假的短格式
    # 樣本，沒抓到，是實跑才抓到的。
    def test_long_form_label_is_normalised_to_classifier_format(self):
        cases = {
            "(S) - Sell To Open": "SellToOpen",
            "(B) - Buy To Open":  "BuyToOpen",
            "(O) - To Open":      "ToOpen",
        }
        for raw, expected in cases.items():
            t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "label": raw}])[0]
            self.assertEqual(t["open_close"], expected, f"{raw} 應正規化為 {expected}")

    def test_already_short_label_is_left_alone(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "label": "BuyToOpen"}])[0]
        self.assertEqual(t["open_close"], "BuyToOpen")

    def test_empty_label_becomes_na(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "label": ""}])[0]
        self.assertEqual(t["open_close"], "N/A")

    def test_blank_trade_condition_becomes_none(self):
        t = scraper.grid_rows_to_trades([{**SAMPLE_ROW, "tradeCondition": "  "}])[0]
        self.assertIsNone(t["trade_condition"])

    def test_row_count_matches_input(self):
        rows = [SAMPLE_ROW, {**SAMPLE_ROW, "strikePrice": 30.0}]
        self.assertEqual(len(scraper.grid_rows_to_trades(rows)), 2)

    def test_empty_input_gives_empty_list(self):
        self.assertEqual(scraper.grid_rows_to_trades([]), [])


class TestCsvPathIsGone(unittest.TestCase):
    """
    迴歸：CSV 末行是 "Downloaded from Barchart.com as of ..." 的頁尾字串，
    舊的 DictReader 沒過濾，每個快照都會多寫一列全 null 的假交易進 DB
    （清掉之前累積 67 列，剛好等於快照組數）。改走 grid 之後這條路不該存在。
    """

    def test_csv_helpers_are_removed(self):
        for name in ("parse_csv_trades", "trigger_csv_download", "wait_for_csv",
                     "to_windows_path", "rename_to_convention", "set_download_path"):
            self.assertFalse(hasattr(scraper, name), f"{name} 應該已經移除")

    def test_no_row_is_all_null(self):
        trades = scraper.grid_rows_to_trades([SAMPLE_ROW])
        for t in trades:
            self.assertIsNotNone(t["option_type"])
            self.assertIsNotNone(t["strike"])
            self.assertIsNotNone(t["premium"])


class TestExtractRowsJs(unittest.TestCase):
    """新增的五個欄位要真的出現在送進頁面的那段 JS 裡，不然轉換函式只會拿到 None。"""

    def test_js_selects_the_five_previously_csv_only_fields(self):
        js = scraper.EXTRACT_ROWS_JS
        for field in ("volume", "openInterest", "volatility", "label", "tradeTime"):
            self.assertIn(field, js, f"EXTRACT_ROWS_JS 少取 {field}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
