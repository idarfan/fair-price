"""
Unit tests for bpus_expirations_scraper.py (bpus.md §3.1 Stage 1).

Covers:
  - success: expirations + underlying_price returned, debug_url included
  - no_candidates: empty expiration dropdown
  - barchart_session_expired: positive session-expiry detection short-circuits
    before reading underlying price / expirations
  - error: no Chrome CDP page found (prepare_page returns (None, None))
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
        "bpus_expirations_scraper",
        __file__.replace("test_bpus_expirations_scraper.py", "bpus_expirations_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["bpus_expirations_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _capture_main(symbol):
    captured = StringIO()
    old_stdout = sys.stdout
    sys.stdout = captured
    try:
        _run(scraper.main(symbol))
    finally:
        sys.stdout = old_stdout
    return json.loads(captured.getvalue().strip())


class TestSuccess(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return False
            if js_expr == scraper.UNDERLYING_JS:
                return 42.5
            if js_expr == scraper.EXPIRATIONS_JS:
                return [ "2026-08-21-m", "2026-09-18-m" ]
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def test_returns_success_with_expirations_and_price(self):
        out = _capture_main("RKLB")
        self.assertEqual(out["status"], "success")
        self.assertEqual(out["expirations"], [ "2026-08-21-m", "2026-09-18-m" ])
        self.assertEqual(out["underlying_price"], 42.5)
        self.assertIn("debug_url", out)
        self.assertIn("RKLB", out["debug_url"])


class TestNoCandidates(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return False
            if js_expr == scraper.UNDERLYING_JS:
                return 42.5
            if js_expr == scraper.EXPIRATIONS_JS:
                return []
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def test_returns_no_candidates_when_dropdown_empty(self):
        out = _capture_main("RKLB")
        self.assertEqual(out["status"], "no_candidates")


class TestSessionExpired(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
        scraper.cdp_navigate = AsyncMock(return_value=None)
        scraper.activate_target = AsyncMock(return_value=None)

        async def fake_eval(ws_url, js_expr, timeout=25):
            if js_expr == scraper.SESSION_EXPIRED_JS:
                return True
            return None

        scraper.cdp_eval = AsyncMock(side_effect=fake_eval)

    def test_returns_session_expired_without_reading_expirations(self):
        out = _capture_main("RKLB")
        self.assertEqual(out["status"], "barchart_session_expired")


class TestNoChromePage(unittest.TestCase):
    def setUp(self):
        scraper.prepare_page = AsyncMock(return_value=(None, None))

    def test_returns_error_when_no_target_found(self):
        out = _capture_main("RKLB")
        self.assertEqual(out["status"], "error")


if __name__ == "__main__":
    unittest.main()
