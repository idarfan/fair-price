"""
Unit tests for pmcc_short_call_scraper.py.

Covers (spec §11):
  - No Delta filtering: a low-Delta row survives _finalize/_merge_vg unchanged
    (grade/passing decisions are Ruby's job, not Python's — spec §6/§7)
  - oi_change: "unch" (non-numeric) -> None passes through, not coerced to 0
  - moneyness: positive/negative values pass through unmodified
  - theoretical_price: correctly mapped from V&G's "theoretical" field via merge
  - _fill_exp_date: forces expiration_date from the URL param when JS field is null
  - _wait_for_grid / _confirm_empty: same three-way classification as leaps_scraper
  - main() happy path / partial (options_prices, volatility_greeks) / no_candidates
"""
import asyncio
import io
import json
import sys
import types
import unittest
from unittest.mock import AsyncMock, patch
import importlib.util


# ---------------------------------------------------------------------------
# Load scraper module with cdp_helper stubbed out
# ---------------------------------------------------------------------------
def _load_scraper():
    stub = types.ModuleType("cdp_helper")
    for name in ("prepare_page", "cdp_eval", "cdp_navigate", "activate_target"):
        setattr(stub, name, AsyncMock())
    sys.modules["cdp_helper"] = stub

    spec = importlib.util.spec_from_file_location(
        "pmcc_short_call_scraper",
        __file__.replace("test_pmcc_short_call_scraper.py", "pmcc_short_call_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["pmcc_short_call_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


# ---------------------------------------------------------------------------
# Pure function tests: _finalize / _merge_vg / _fill_exp_date
# ---------------------------------------------------------------------------
class TestFillExpDate(unittest.TestCase):

    def test_fills_null_expiration_date_from_url_param(self):
        rows = [{"strike": 13.0, "expiration_date": None}]
        scraper._fill_exp_date(rows, "2026-07-17")
        self.assertEqual(rows[0]["expiration_date"], "2026-07-17")

    def test_does_not_overwrite_existing_expiration_date(self):
        rows = [{"strike": 13.0, "expiration_date": "2026-07-24"}]
        scraper._fill_exp_date(rows, "2026-07-17")
        self.assertEqual(rows[0]["expiration_date"], "2026-07-24")


class TestNoDeltaFiltering(unittest.TestCase):
    """spec §6/§7: Python 不硬濾 Delta，交 Ruby 的 PmccRankingService 處理。"""

    def test_low_delta_row_survives_finalize_unmodified(self):
        rows = [{"strike": 20.0, "expiration_date": "2026-07-17", "delta": 0.03, "iv": 0.5}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["delta"], 0.03)

    def test_high_delta_row_also_survives_unmodified(self):
        rows = [{"strike": 5.0, "expiration_date": "2026-07-17", "delta": 0.95, "iv": 0.5}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertEqual(out[0]["delta"], 0.95)

    def test_merge_vg_does_not_drop_rows_by_delta(self):
        opts = [
            {"strike": 5.0, "expiration_date": "2026-07-17", "delta": 0.02},
            {"strike": 13.0, "expiration_date": "2026-07-17", "delta": 0.90},
        ]
        merged = scraper._merge_vg(opts, vg_rows=[])
        self.assertEqual(len(merged), 2)


class TestOiChangeUnch(unittest.TestCase):

    def test_unch_oi_change_passes_through_as_none_not_zero(self):
        # Browser-side: typeof r.openInterestChange==='number' fails for "unch" string,
        # falls through to null — simulated here as oi_chg=None already resolved by JS.
        rows = [{"strike": 13.0, "expiration_date": "2026-07-17", "oi_chg": None}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertIsNone(out[0]["oi_change"])
        self.assertNotEqual(out[0]["oi_change"], 0)

    def test_numeric_oi_change_passes_through(self):
        rows = [{"strike": 13.0, "expiration_date": "2026-07-17", "oi_chg": 3912}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertEqual(out[0]["oi_change"], 3912)


class TestMoneynessSign(unittest.TestCase):

    def test_negative_moneyness_preserved(self):
        rows = [{"strike": 13.0, "expiration_date": "2026-07-17", "moneyness": -0.045}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertEqual(out[0]["moneyness"], -0.045)

    def test_positive_moneyness_preserved(self):
        rows = [{"strike": 10.0, "expiration_date": "2026-07-17", "moneyness": 0.245}]
        out = scraper._finalize(rows, underlying_price=12.44)
        self.assertEqual(out[0]["moneyness"], 0.245)


class TestTheoreticalPrice(unittest.TestCase):

    def test_merge_maps_vg_theoretical_to_theoretical_price(self):
        opts = [{"strike": 13.0, "expiration_date": "2026-07-17", "bid": 0.23, "ask": 0.25}]
        vg = [{"strike": 13.0, "expiration_date": "2026-07-17", "theoretical": 0.24}]
        merged = scraper._merge_vg(opts, vg)
        out = scraper._finalize(merged, underlying_price=12.44)
        self.assertEqual(out[0]["theoretical_price"], 0.24)

    def test_no_matching_vg_row_leaves_theoretical_price_none(self):
        opts = [{"strike": 13.0, "expiration_date": "2026-07-17"}]
        vg = [{"strike": 99.0, "expiration_date": "2026-07-17", "theoretical": 0.24}]
        merged = scraper._merge_vg(opts, vg)
        out = scraper._finalize(merged, underlying_price=12.44)
        self.assertIsNone(out[0]["theoretical_price"])

    def test_vg_iv_delta_preferred_over_options_prices_iv_delta(self):
        opts = [{"strike": 13.0, "expiration_date": "2026-07-17", "iv": 0.70, "delta": 0.30}]
        vg = [{"strike": 13.0, "expiration_date": "2026-07-17", "iv": 0.7163, "delta": 0.3339}]
        merged = scraper._merge_vg(opts, vg)
        self.assertEqual(merged[0]["iv"], 0.7163)
        self.assertEqual(merged[0]["delta"], 0.3339)


# ---------------------------------------------------------------------------
# _wait_for_grid / _confirm_empty — same three-way classification as leaps_scraper
# ---------------------------------------------------------------------------
class TestWaitForGrid(unittest.TestCase):

    def test_returns_data_immediately(self):
        rows = [{"strike": 13.0}]
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=rows)):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=5))
        self.assertEqual(result, rows)

    def test_returns_empty_list_immediately(self):
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=[])):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=2))
        self.assertEqual(result, [])

    def test_returns_none_on_timeout(self):
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=None)):
            result = _run(scraper._wait_for_grid("ws://", "JS", max_wait_s=0.05, poll_s=0.01))
        self.assertIsNone(result)


class TestConfirmEmpty(unittest.TestCase):

    def test_still_empty_after_delay(self):
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=[])):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertEqual(result, [])

    def test_data_appeared_after_delay(self):
        rows = [{"strike": 13.0}]
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=rows)):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertEqual(result, rows)

    def test_grid_unmounted_returns_none(self):
        with patch("pmcc_short_call_scraper.cdp_eval", new=AsyncMock(return_value=None)):
            result = _run(scraper._confirm_empty("ws://", "JS", delay_s=0.001))
        self.assertIsNone(result)


# ---------------------------------------------------------------------------
# main() integration — routed cdp_eval mocks
# ---------------------------------------------------------------------------
GOOD_EXPIRATIONS = ["2026-07-17-m", "2026-07-24-w", "2026-07-31-w"]
GOOD_OPTS = [
    {"strike": 13.0, "expiration_date": "2026-07-17", "dte": 6,
     "bid": 0.23, "ask": 0.25, "mid": 0.24, "last": 0.23,
     "volume": 5285, "oi": 26278, "oi_chg": 3912, "moneyness": -0.045,
     "delta": 0.3339, "iv": 0.7163, "change": None, "pct_change": None},
]
GOOD_VG = [
    {"strike": 13.0, "expiration_date": "2026-07-17", "theoretical": 0.24,
     "iv": 0.7163, "delta": 0.3339, "gamma": 0.3185, "theta": -0.0349,
     "vega": 0.0058, "rho": 0.0006, "itm_prob": 0.3158, "vol_oi": 0.20},
]


def _capture_main(cdp_eval_mock, wait_mock=None, confirm_mock=None):
    patches = [
        patch("pmcc_short_call_scraper.prepare_page", new=AsyncMock(return_value=("tid", "ws://fake"))),
        patch("pmcc_short_call_scraper.cdp_navigate", new=AsyncMock()),
        patch("pmcc_short_call_scraper.activate_target", new=AsyncMock()),
        patch("pmcc_short_call_scraper.cdp_eval", new=cdp_eval_mock),
    ]
    if wait_mock:
        patches.append(patch("pmcc_short_call_scraper._wait_for_grid", new=wait_mock))
    if confirm_mock:
        patches.append(patch("pmcc_short_call_scraper._confirm_empty", new=confirm_mock))

    buf = io.StringIO()
    for p in patches:
        p.start()
    try:
        with patch("sys.stdout", buf):
            _run(scraper.main("NOK"))
    finally:
        for p in patches:
            p.stop()
    out = buf.getvalue().strip()
    return json.loads(out) if out else None


def _stage1_eval():
    async def side(ws, js, **kw):
        if "bc-overlay-modal" in js:
            return False
        if "angular.element" in js:            # UNDERLYING_JS
            return 12.44
        if "querySelectorAll('select')" in js:  # EXPIRATIONS_JS
            return GOOD_EXPIRATIONS
        return None
    return AsyncMock(side_effect=side)


class TestNoCandidates(unittest.TestCase):

    def test_empty_expiration_dropdown(self):
        async def side(ws, js, **kw):
            if "querySelectorAll('select')" in js:
                return []
            if "angular.element" in js:
                return 12.44
            return False
        result = _capture_main(AsyncMock(side_effect=side))
        self.assertEqual(result["status"], "no_candidates")


class TestHappyPath(unittest.TestCase):

    def test_success_three_expirations(self):
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "bidPrice" in js:
                return GOOD_OPTS
            if "itmProbability" in js:
                return GOOD_VG
            return None

        result = _capture_main(_stage1_eval(), wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["expirations"], ["2026-07-17", "2026-07-24", "2026-07-31"])
        # 3 expirations x 1 row each (GOOD_OPTS has one row, reused for every expiration)
        self.assertEqual(len(result["rows"]), 3)
        self.assertEqual(result["rows"][0]["theoretical_price"], 0.24)
        self.assertEqual(result["underlying_price"], 12.44)


class TestPartialOptionsPrices(unittest.TestCase):

    def test_timeout_on_options_prices_reports_page_load_timeout(self):
        async def wait_side(ws, js, max_wait_s=30, **kw):
            return None  # every _wait_for_grid call times out

        result = _capture_main(_stage1_eval(), wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["expired_layer"], "options_prices")
        self.assertEqual(result["expired_at_expiration"], "2026-07-17")
        self.assertEqual(result["reason"], "page_load_timeout")

    def test_session_expired_detected(self):
        async def side(ws, js, **kw):
            if "bc-overlay-modal" in js:
                return True   # session expired modal present
            if "angular.element" in js:
                return 12.44
            if "querySelectorAll('select')" in js:
                return GOOD_EXPIRATIONS
            return None

        async def wait_side(ws, js, max_wait_s=30, **kw):
            return None

        result = _capture_main(AsyncMock(side_effect=side), wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["reason"], "session_expired")


class TestPartialVolatilityGreeks(unittest.TestCase):

    def test_timeout_on_vg_after_successful_options_prices(self):
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "bidPrice" in js:
                return GOOD_OPTS
            return None  # V&G always times out

        result = _capture_main(_stage1_eval(), wait_mock=AsyncMock(side_effect=wait_side))
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["expired_layer"], "volatility_greeks")
        self.assertEqual(result["expired_at_expiration"], "2026-07-17")
        # rows from the already-succeeded options_prices call must not be discarded
        self.assertEqual(len(result["rows"]), 1)


class TestConfirmedEmptySkip(unittest.TestCase):

    def test_options_prices_confirmed_empty_skips_expiration_non_fatal(self):
        async def wait_side(ws, js, max_wait_s=30, **kw):
            if "bidPrice" in js:
                return []       # immediate empty -> triggers stability check
            if "itmProbability" in js:
                return GOOD_VG
            return None

        async def confirm_side(ws_url, js_expr, delay_s=1.5):
            if "bidPrice" in js_expr:
                return []       # still empty after stability check -> skip, non-fatal
            return GOOD_VG

        result = _capture_main(
            _stage1_eval(),
            wait_mock=AsyncMock(side_effect=wait_side),
            confirm_mock=AsyncMock(side_effect=confirm_side),
        )
        self.assertEqual(result["status"], "success")
        self.assertEqual(len(result["skipped_expirations"]), 3)
        self.assertTrue(all(s["layer"] == "options_prices" for s in result["skipped_expirations"]))


if __name__ == "__main__":
    unittest.main()
