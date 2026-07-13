"""
Unit tests for bpus_put_chain_scraper.py (bpus.md §3.2 Stage 2).

Covers:
  - success: Put-side rows returned with underlying_price + debug_url,
    expiration_date filled from the URL param when the JS field is null
  - no_candidates: grid confirmed empty after the stability re-check
  - barchart_session_expired: detected when the grid never loads
  - error: grid load timeout that is NOT a session-expiry
"""
import asyncio
import json
import sys
import types
import unittest
from unittest.mock import AsyncMock
import importlib.util
from io import StringIO


def _load_scraper():
    stub = types.ModuleType("cdp_helper")
    for name in ("prepare_page", "cdp_eval", "cdp_navigate", "activate_target"):
        setattr(stub, name, AsyncMock())
    sys.modules["cdp_helper"] = stub

    spec = importlib.util.spec_from_file_location(
        "bpus_put_chain_scraper",
        __file__.replace("test_bpus_put_chain_scraper.py", "bpus_put_chain_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["bpus_put_chain_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _capture_main(symbol, expiration):
    captured = StringIO()
    old_stdout = sys.stdout
    sys.stdout = captured
    try:
        _run(scraper.main(symbol, expiration))
    finally:
        sys.stdout = old_stdout
    return json.loads(captured.getvalue().strip())


ROWS = [
    {"strike": 40.0, "bid": 1.10, "ask": 1.30, "last": 1.20, "volume": 120,
     "open_interest": 500, "iv": 0.55, "delta": -0.30, "expiration_date": None},
]


class TestFillExpDate(unittest.TestCase):
    def test_fills_null_expiration_date_from_url_param(self):
        rows = [ { "strike": 40.0, "expiration_date": None } ]
        scraper._fill_exp_date(rows, "2026-08-21")
        self.assertEqual(rows[0]["expiration_date"], "2026-08-21")

    def test_does_not_overwrite_existing_expiration_date(self):
        rows = [ { "strike": 40.0, "expiration_date": "2026-08-28" } ]
        scraper._fill_exp_date(rows, "2026-08-21")
        self.assertEqual(rows[0]["expiration_date"], "2026-08-28")


class TestSuccess(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.PUT_CHAIN_JS:
                return [ dict(r) for r in ROWS ]
            if js_expr == scraper.UNDERLYING_JS:
                return 42.5
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return False
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def test_returns_success_with_rows_and_price(self):
        out = _capture_main("RKLB", "2026-08-21-m")
        self.assertEqual(out["status"], "success")
        self.assertEqual(len(out["rows"]), 1)
        self.assertEqual(out["rows"][0]["strike"], 40.0)
        self.assertEqual(out["underlying_price"], 42.5)
        self.assertIn("debug_url", out)

    def test_fills_expiration_date_from_url_expiration(self):
        out = _capture_main("RKLB", "2026-08-21-m")
        self.assertEqual(out["rows"][0]["expiration_date"], "2026-08-21")


class TestNoCandidatesAfterStabilityCheck(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.PUT_CHAIN_JS:
                return []  # confirmed empty both times
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return False
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def test_returns_no_candidates_when_confirmed_empty(self):
        out = _capture_main("RKLB", "2026-08-21-m")
        self.assertEqual(out["status"], "no_candidates")


class TestSessionExpiredWhenGridNeverLoads(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)
        self._orig_grid_max_wait_s = scraper.GRID_MAX_WAIT_S
        scraper.GRID_MAX_WAIT_S = 0  # force immediate timeout in test

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.PUT_CHAIN_JS:
                return None  # grid never mounts
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return True
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def tearDown(self):
        scraper.GRID_MAX_WAIT_S = self._orig_grid_max_wait_s

    def test_returns_session_expired(self):
        out = _capture_main("RKLB", "2026-08-21-m")
        self.assertEqual(out["status"], "barchart_session_expired")


class TestGridTimeoutNotSessionExpired(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)
        self._orig_grid_max_wait_s = scraper.GRID_MAX_WAIT_S
        scraper.GRID_MAX_WAIT_S = 0

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.PUT_CHAIN_JS:
                return None
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return False
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def tearDown(self):
        scraper.GRID_MAX_WAIT_S = self._orig_grid_max_wait_s

    def test_returns_generic_error(self):
        out = _capture_main("RKLB", "2026-08-21-m")
        self.assertEqual(out["status"], "error")


if __name__ == "__main__":
    unittest.main()
