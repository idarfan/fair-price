"""
Unit tests for leaps_spread_expirations_scraper.py（LEAPS 垂直價差專用，與 bcvs 分開）。

讀不到到期日時依 DOM 分流（leaps-call-spread-spec P0 第 13 步實測）：
  - .bc-error-404-page 存在                      → symbol_not_found（ZZZZQ）
  - .error-page 顯示 "no option data"           → no_options（BRK.A）
  - 其他                                         → no_candidates
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
        "leaps_spread_expirations_scraper",
        __file__.replace("test_leaps_spread_expirations_scraper.py", "leaps_spread_expirations_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["leaps_spread_expirations_scraper"] = mod
    spec.loader.exec_module(mod)
    return mod


scraper = _load_scraper()


def _capture_main(symbol):
    captured = StringIO()
    old_stdout = sys.stdout
    sys.stdout = captured
    try:
        asyncio.run(scraper.main(symbol))
    finally:
        sys.stdout = old_stdout
    return json.loads(captured.getvalue().strip())


def _setup(page_state=None, expirations=None, expired=False):
    scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
    scraper.cdp_navigate = AsyncMock(return_value=None)
    scraper.activate_target = AsyncMock(return_value=None)
    scraper.asyncio.sleep = AsyncMock(return_value=None)

    async def fake_eval(ws_url, js_expr, timeout=25, **_):
        if js_expr == scraper.SESSION_EXPIRED_JS:
            return expired
        if js_expr == scraper.EXPIRATIONS_JS:
            return expirations or []
        if js_expr == scraper.PAGE_STATE_JS:
            return page_state
        if js_expr == scraper.UNDERLYING_JS:
            return 139.54
        return None

    scraper.cdp_eval = AsyncMock(side_effect=fake_eval)


class TestSuccess(unittest.TestCase):
    def test_returns_expirations_and_underlying(self):
        _setup(expirations=["2027-10-15-m", "2028-01-21-m"])
        result = _capture_main("orcl")
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["expirations"], ["2027-10-15-m", "2028-01-21-m"])
        self.assertEqual(result["underlying_price"], 139.54)
        self.assertIn("/ORCL/options", result["debug_url"])

    def test_page_state_is_not_consulted_when_expirations_exist(self):
        _setup(page_state="not_found", expirations=["2027-10-15-m"])
        self.assertEqual(_capture_main("ORCL")["status"], "success")


class TestEmptyExpirationsClassification(unittest.TestCase):
    def test_404_page_is_symbol_not_found(self):
        _setup("not_found")
        self.assertEqual(_capture_main("ZZZZQ"), {"status": "symbol_not_found"})

    def test_no_option_data_page_is_no_options(self):
        _setup("no_options")
        self.assertEqual(_capture_main("BRK.A"), {"status": "no_options"})

    def test_anything_else_stays_no_candidates(self):
        _setup(None)
        self.assertEqual(_capture_main("ORCL"), {"status": "no_candidates"})


class TestSessionAndCdp(unittest.TestCase):
    def test_session_expired(self):
        _setup(expired=True)
        self.assertEqual(_capture_main("ORCL"), {"status": "barchart_session_expired"})

    def test_no_cdp_page(self):
        _setup()
        scraper.prepare_page = AsyncMock(return_value=(None, None))
        self.assertEqual(_capture_main("ORCL")["status"], "error")


if __name__ == "__main__":
    unittest.main(verbosity=2)
