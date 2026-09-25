"""
Unit tests for bcvs_expirations_scraper.py 的「讀不到到期日」分流。

2026-09-25（leaps-call-spread-spec P0 第 13 步）：原本查無代號與沒有選擇權都回
no_candidates，LEAPS 垂直價差需要分成兩種錯誤訊息。判定依據是 DOM 實際內容：
  - .bc-error-404-page 存在                         → symbol_not_found（ZZZZQ 實測）
  - .error-page 顯示 "no option data" 且無到期日    → no_options（BRK.A 實測）
  - 其他讀不到的情況                                 → 維持 no_candidates
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
        "bcvs_expirations_scraper",
        __file__.replace("test_bcvs_expirations_scraper.py", "bcvs_expirations_scraper.py"),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["bcvs_expirations_scraper"] = mod
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


def _setup(page_state, expirations=None):
    scraper.prepare_page = AsyncMock(return_value=("target-1", "ws://fake"))
    scraper.cdp_navigate = AsyncMock(return_value=None)
    scraper.activate_target = AsyncMock(return_value=None)
    scraper.asyncio.sleep = AsyncMock(return_value=None)

    async def fake_eval(ws_url, js_expr, timeout=25, **_):
        if js_expr == scraper.SESSION_EXPIRED_JS:
            return False
        if js_expr == scraper.EXPIRATIONS_JS:
            return expirations or []
        if js_expr == scraper.PAGE_STATE_JS:
            return page_state
        return None

    scraper.cdp_eval = AsyncMock(side_effect=fake_eval)


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

    def test_page_state_is_not_consulted_when_expirations_exist(self):
        _setup("not_found", expirations=["2027-10-15-m"])
        result = _capture_main("ORCL")
        self.assertEqual(result["status"], "success")


if __name__ == "__main__":
    unittest.main(verbosity=2)
