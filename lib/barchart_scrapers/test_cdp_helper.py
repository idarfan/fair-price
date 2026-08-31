"""
cdp_helper.cdp_eval 的重試行為測試。

背景：Windows Chrome 會凍結背景分頁，凍結期間 Runtime.evaluate 完全不回應。
2026-08-31 SONY 查詢整趟炸在 "TimeoutError: CDP eval timed out"，修法是逾時後
先把分頁 activate 起來（解凍 renderer）再試一次。這支測試釘住那個行為，
以及「沒有 target_id 就沒有辦法解凍，不該白白多等一輪」這個邊界。

實際的 WebSocket 往返在 _cdp_eval_once，這裡一律 patch 掉——這支測試要驗的是
重試決策，不是 CDP 協定本身。
"""
import asyncio
import sys
import unittest
import importlib.util
from unittest.mock import AsyncMock, patch


def _load_helper():
    # websockets 只有 _cdp_eval_once 會用到，這裡不需要真的安裝
    spec = importlib.util.spec_from_file_location(
        "cdp_helper", __file__.replace("test_cdp_helper.py", "cdp_helper.py")
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["cdp_helper"] = mod
    spec.loader.exec_module(mod)
    return mod


helper = _load_helper()


def _run(coro):
    return asyncio.run(coro)


class TestCdpEvalRetry(unittest.TestCase):

    def test_returns_value_without_retrying_when_first_attempt_succeeds(self):
        once = AsyncMock(return_value=[{"strike": 7}])
        activate = AsyncMock()

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=activate):
            result = _run(helper.cdp_eval("ws://", "JS", target_id="T1"))

        self.assertEqual(result, [{"strike": 7}])
        self.assertEqual(once.await_count, 1)
        activate.assert_not_awaited()

    def test_reactivates_tab_and_retries_after_timeout(self):
        """凍結分頁的正常情境：第一次逾時 → activate → 第二次成功。"""
        once = AsyncMock(side_effect=[TimeoutError("CDP eval timed out"), "ok"])
        activate = AsyncMock()

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=activate), \
             patch.object(helper.asyncio, "sleep", new=AsyncMock()):
            result = _run(helper.cdp_eval("ws://", "JS", target_id="T1"))

        self.assertEqual(result, "ok")
        self.assertEqual(once.await_count, 2)
        activate.assert_awaited_once_with("T1")

    def test_raises_after_all_attempts_time_out(self):
        once = AsyncMock(side_effect=TimeoutError("CDP eval timed out"))
        activate = AsyncMock()

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=activate), \
             patch.object(helper.asyncio, "sleep", new=AsyncMock()):
            with self.assertRaises(TimeoutError):
                _run(helper.cdp_eval("ws://", "JS", target_id="T1", attempts=3))

        self.assertEqual(once.await_count, 3)
        self.assertEqual(activate.await_count, 2)   # 每次重試前各一次

    def test_does_not_retry_without_target_id(self):
        """沒有 target_id 就沒辦法解凍分頁，重試只是白等一輪 timeout。"""
        once = AsyncMock(side_effect=TimeoutError("CDP eval timed out"))
        activate = AsyncMock()

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=activate):
            with self.assertRaises(TimeoutError):
                _run(helper.cdp_eval("ws://", "JS"))

        self.assertEqual(once.await_count, 1)
        activate.assert_not_awaited()

    def test_asyncio_timeout_error_is_treated_the_same(self):
        """asyncio.TimeoutError 與內建 TimeoutError 在舊版 Python 不是同一個類別。"""
        once = AsyncMock(side_effect=[asyncio.TimeoutError(), "ok"])

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=AsyncMock()), \
             patch.object(helper.asyncio, "sleep", new=AsyncMock()):
            result = _run(helper.cdp_eval("ws://", "JS", target_id="T1"))

        self.assertEqual(result, "ok")

    def test_non_timeout_errors_are_not_retried(self):
        """頁面丟出的 JS 例外（RuntimeError）不是凍結，重試也沒用，要立刻冒出去。"""
        once = AsyncMock(side_effect=RuntimeError("exceptionDetails"))
        activate = AsyncMock()

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=activate):
            with self.assertRaises(RuntimeError):
                _run(helper.cdp_eval("ws://", "JS", target_id="T1"))

        self.assertEqual(once.await_count, 1)
        activate.assert_not_awaited()

    def test_attempts_below_one_still_runs_once(self):
        once = AsyncMock(return_value="ok")

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=AsyncMock()):
            result = _run(helper.cdp_eval("ws://", "JS", target_id="T1", attempts=0))

        self.assertEqual(result, "ok")
        self.assertEqual(once.await_count, 1)

    def test_timeout_is_passed_through_to_the_single_eval(self):
        once = AsyncMock(return_value="ok")

        with patch.object(helper, "_cdp_eval_once", new=once), \
             patch.object(helper, "activate_target", new=AsyncMock()):
            _run(helper.cdp_eval("ws://url", "JS EXPR", timeout=7, target_id="T1"))

        once.assert_awaited_once_with("ws://url", "JS EXPR", 7)


if __name__ == "__main__":
    unittest.main(verbosity=2)
