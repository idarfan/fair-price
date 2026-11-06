"""
barchart_iv_history_scraper.py 的單元測試（leaps-iv-environment P2）。cdp_helper 以 stub 取代，不連 Chrome。

涵蓋：
  latest／backfill 切換到對應區間（1M／2Y），latest 只回最新一列
  區間本來就是目標值時不切回、原本是別的區間時結束前切回
  表格載入不出來 → session 過期 vs 一般錯誤
  區間清單沒有目標選項 → error
  HV、報價日期讀不到時回 null（由 Ruby 判定失敗），不拋例外
"""
import asyncio
import io
import json
import sys
import types
import unittest
from unittest.mock import AsyncMock, patch
import importlib.util


def _load():
    stub = types.ModuleType("cdp_helper")
    for name in ("prepare_page", "cdp_eval", "cdp_navigate", "activate_target"):
        setattr(stub, name, AsyncMock())
    sys.modules["cdp_helper"] = stub
    spec = importlib.util.spec_from_file_location(
        "barchart_iv_history_scraper",
        __file__.replace("test_barchart_iv_history_scraper.py", "barchart_iv_history_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["barchart_iv_history_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load()

ROWS_BY_PERIOD = {
    "1M": [{"date": f"2026-11-0{5 - i}", "impliedVolatilityPercentile1y": 0.92} for i in range(3)],
    "3M": [{"date": f"2026-10-{30 - i}", "impliedVolatilityPercentile1y": 0.5} for i in range(5)],
    "2Y": [{"date": f"2026-11-0{5 - i}", "impliedVolatilityPercentile1y": 0.92} for i in range(4)],
}


class FakePage:
    """模擬 options-history 頁：點擊區間選項後，表格換成該區間的資料。"""

    def __init__(self, active="3M", grid=True, expired=False, options=("1M", "3M", "6M", "1Y", "2Y"),
                 hv=46.66, quote="11/05/26"):
        self.active, self.grid, self.expired = active, grid, expired
        self.options, self.hv, self.quote = list(options), hv, quote
        self.clicks, self.navigated = [], []

    async def eval(self, ws, js, **kw):
        if js == scraper.GRID_JS:
            return ROWS_BY_PERIOD.get(self.active) if self.grid else None
        if js == scraper.PERIOD_STATE_JS:
            return {"active": self.active, "options": self.options}
        if js == scraper.SESSION_EXPIRED_JS:
            return self.expired
        if js == scraper.QUOTE_DATE_JS:
            return self.quote
        if js == scraper.HV_JS:
            return self.hv
        if "#bc-price-history-time-frame li" in js and ".click()" in js:
            label = json.loads(js.rsplit("(", 1)[1].rstrip(")\n "))
            if label not in self.options:
                return False
            self.clicks.append(label)
            self.active = label
            return True
        return True  # 開關下拉選單

    async def nav(self, ws, url, settle_ms=0):
        self.navigated.append(url)


def run_main(page, mode):
    buf = io.StringIO()
    with (
        patch("barchart_iv_history_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
        patch("barchart_iv_history_scraper.cdp_eval", new=AsyncMock(side_effect=page.eval)),
        patch("barchart_iv_history_scraper.cdp_navigate", new=AsyncMock(side_effect=page.nav)),
        patch("barchart_iv_history_scraper.activate_target", new=AsyncMock()),
        patch("barchart_iv_history_scraper.asyncio.sleep", new=AsyncMock()),
        patch("sys.stdout", buf),
    ):
        asyncio.run(scraper.main("tsm", mode))
    return json.loads(buf.getvalue().strip())


class TestModes(unittest.TestCase):
    def test_latest_selects_1m_returns_newest_row_and_restores_original_period(self):
        page = FakePage(active="3M")
        out = run_main(page, "latest")

        self.assertEqual(out["status"], "success")
        self.assertEqual(out["period_label"], "1M")
        self.assertEqual([r["date"] for r in out["rows"]], ["2026-11-05"])
        self.assertEqual(page.clicks, ["1M", "3M"], "結束前要切回使用者原本的 3M")
        self.assertEqual((out["original_period"], out["restored_period"]), ("3M", "3M"))
        self.assertEqual(out["source_url"], "https://www.barchart.com/stocks/quotes/TSM/options-history")

    def test_backfill_selects_2y_and_returns_all_rows(self):
        out = run_main(FakePage(active="3M"), "backfill")

        self.assertEqual(out["period_label"], "2Y")
        self.assertEqual(len(out["rows"]), len(ROWS_BY_PERIOD["2Y"]))

    def test_already_on_target_period_still_clicks_but_does_not_restore(self):
        # Barchart 記住上次的區間：即使已是 2Y 也要明確點選，結束時不必切回
        page = FakePage(active="2Y")
        out = run_main(page, "backfill")

        self.assertEqual(page.clicks, ["2Y"])
        self.assertIsNone(out["restored_period"])

    def test_hv_read_from_overview_page(self):
        page = FakePage()
        out = run_main(page, "latest")

        self.assertEqual(out["hv_pct"], 46.66)
        self.assertEqual(page.navigated, ["https://www.barchart.com/stocks/quotes/TSM/overview"])
        self.assertEqual(out["quote_date_text"], "11/05/26")


class TestFailures(unittest.TestCase):
    def test_grid_never_loads_and_session_expired(self):
        self.assertEqual(run_main(FakePage(grid=False, expired=True), "latest"),
                         {"status": "barchart_session_expired"})

    def test_grid_never_loads_without_session_problem_is_error(self):
        out = run_main(FakePage(grid=False, expired=False), "latest")
        self.assertEqual(out["status"], "error")
        self.assertIn("非 Session 問題", out["error"])

    def test_missing_period_option_is_error(self):
        out = run_main(FakePage(options=("1M", "3M")), "backfill")
        self.assertEqual(out["status"], "error")
        self.assertIn("2Y", out["error"])

    def test_unreadable_hv_and_quote_date_are_null_not_exceptions(self):
        out = run_main(FakePage(hv=None, quote=None), "latest")
        self.assertEqual(out["status"], "success")
        self.assertIsNone(out["hv_pct"])
        self.assertIsNone(out["quote_date_text"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
