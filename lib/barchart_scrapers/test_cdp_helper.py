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
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
import importlib.util
from pathlib import Path
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


def _tab(tid):
    return {"id": tid, "type": "page", "url": "about:blank", "webSocketDebuggerUrl": f"ws://{tid}"}


class _TabStateMixin:
    """每個測試用自己的追蹤目錄與乾淨的「本程序開過的分頁」清單。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._dir_patch = patch.object(helper, "TAB_TRACK_DIR", Path(self._tmp.name))
        self._dir_patch.start()
        helper._OWNED_TABS.clear()

    def tearDown(self):
        helper._OWNED_TABS.clear()
        self._dir_patch.stop()
        self._tmp.cleanup()


class TestGetTarget(_TabStateMixin, unittest.TestCase):
    """
    2026-10-01：原本沒有完全符合的分頁時會借用任一 Barchart 分頁再導航。
    兩個不同代號的抓取同時進行時會搶到同一個分頁、把對方導航走——失敗，
    或讀到別的代號的資料。改成每次抓取開自己的專屬分頁，抓完關掉。
    """

    def test_always_opens_a_dedicated_tab_even_if_exact_page_exists(self):
        with patch.object(helper, "_list_targets") as list_targets, \
             patch.object(helper, "_open_blank_tab", return_value=_tab("N")) as open_tab, \
             patch.object(helper, "_sweep_orphan_tabs"):
            self.assertEqual(helper.get_target("ORCL", "options"), ("N", "ws://N"))
        open_tab.assert_called_once_with()
        list_targets.assert_not_called()   # 不看既有分頁，也就不可能借到別人的

    def test_records_the_tab_as_owned_and_writes_a_tracking_file(self):
        with patch.object(helper, "_open_blank_tab", return_value=_tab("N")), \
             patch.object(helper, "_sweep_orphan_tabs"):
            helper.get_target("ORCL", "options")
        self.assertEqual(helper._OWNED_TABS, ["N"])
        self.assertTrue((helper.TAB_TRACK_DIR / "N").exists())

    def test_sweeps_orphans_before_opening(self):
        calls = []
        with patch.object(helper, "_sweep_orphan_tabs", side_effect=lambda: calls.append("sweep")), \
             patch.object(helper, "_open_blank_tab", side_effect=lambda: calls.append("open") or _tab("N")):
            helper.get_target("ORCL", "options")
        self.assertEqual(calls, ["sweep", "open"])

    def test_returns_none_when_opening_tab_fails(self):
        with patch.object(helper, "_open_blank_tab", side_effect=OSError("refused")), \
             patch.object(helper, "_sweep_orphan_tabs"):
            self.assertEqual(helper.get_target("ORCL", "options"), (None, None))
        self.assertEqual(helper._OWNED_TABS, [])

    def test_installs_exit_handlers_once(self):
        with patch.object(helper, "_open_blank_tab", side_effect=[_tab("A"), _tab("B")]), \
             patch.object(helper, "_sweep_orphan_tabs"), \
             patch.object(helper, "_install_exit_handlers") as install:
            helper.get_target("ORCL", "options")
            helper.get_target("ORCL", "volatility-greeks")
        self.assertEqual(install.call_count, 2)   # 冪等：呼叫端不必記得只裝一次
        self.assertEqual(helper._OWNED_TABS, ["A", "B"])


class TestCloseOwnedTabs(_TabStateMixin, unittest.TestCase):

    def test_closes_every_owned_tab_and_removes_tracking_files(self):
        for tid in ("A", "B"):
            helper._OWNED_TABS.append(tid)
            (helper.TAB_TRACK_DIR / tid).write_text("0")
        with patch.object(helper, "_close_tab") as close:
            helper.close_owned_tabs()
        self.assertEqual([c.args[0] for c in close.call_args_list], ["A", "B"])
        self.assertEqual(helper._OWNED_TABS, [])
        self.assertEqual(list(helper.TAB_TRACK_DIR.iterdir()), [])

    def test_one_failing_close_does_not_stop_the_rest(self):
        helper._OWNED_TABS.extend(["A", "B"])
        with patch.object(helper, "_close_tab", side_effect=[OSError("gone"), None]) as close:
            helper.close_owned_tabs()
        self.assertEqual(close.call_count, 2)
        self.assertEqual(helper._OWNED_TABS, [])

    def test_close_tab_hits_cdp_base(self):
        """leaps-call-spread-spec：cdp_helper 每個 urlopen 目標都必須以 {CDP_BASE} 開頭。"""
        response = unittest.mock.MagicMock()
        with patch.object(helper.urllib.request, "urlopen", return_value=response) as urlopen:
            helper._close_tab("T9")
        target = urlopen.call_args.args[0]
        url = target.full_url if hasattr(target, "full_url") else target
        self.assertEqual(url, f"{helper.CDP_BASE}/json/close/T9")


class TestSweepOrphanTabs(_TabStateMixin, unittest.TestCase):
    """被 SIGKILL 的爬蟲沒有機會關分頁；下次開分頁前清掉過期的。"""

    def test_closes_only_tabs_older_than_orphan_age(self):
        now = time.time()
        old, fresh = helper.TAB_TRACK_DIR / "OLD", helper.TAB_TRACK_DIR / "FRESH"
        old.write_text("x")
        fresh.write_text("x")
        os.utime(old, (now - helper.ORPHAN_AGE_S - 10,) * 2)
        with patch.object(helper, "_close_tab") as close:
            helper._sweep_orphan_tabs()
        close.assert_called_once_with("OLD")
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())

    def test_orphan_age_exceeds_the_longest_scraper(self):
        # LEAPS 爬蟲沒有外層時限、實測 3–5 分鐘；不能把還在跑的分頁當孤兒關掉。
        self.assertGreaterEqual(helper.ORPHAN_AGE_S, 30 * 60)

    def test_missing_directory_is_not_an_error(self):
        with patch.object(helper, "TAB_TRACK_DIR", Path(self._tmp.name) / "nope"):
            helper._sweep_orphan_tabs()

    def test_foreign_directory_inside_track_dir_is_ignored(self):
        """
        2026-10-01 事故：hook 在 tmp/cdp_tabs/ 底下建了一個 .claude/ 資料夾。滿 30 分鐘後
        清理把它當孤兒分頁，unlink 一個資料夾丟出 IsADirectoryError，**所有爬蟲**每次都失敗。
        追蹤目錄是共用位置，裡面出現什麼都不能讓抓取失敗。
        """
        stray = helper.TAB_TRACK_DIR / ".claude"
        (stray / ".cc-writes").mkdir(parents=True)
        old = time.time() - helper.ORPHAN_AGE_S - 10
        os.utime(stray, (old, old))
        with patch.object(helper, "_close_tab") as close:
            helper._sweep_orphan_tabs()
        close.assert_not_called()
        self.assertTrue(stray.is_dir())   # 不是我們的東西，不碰

    def test_sweep_never_raises_on_filesystem_errors(self):
        entry = helper.TAB_TRACK_DIR / "OLD"
        entry.write_text("x")
        old = time.time() - helper.ORPHAN_AGE_S - 10
        os.utime(entry, (old, old))
        with patch.object(helper, "_close_tab"), \
             patch.object(helper, "_forget_tab", side_effect=PermissionError("denied")):
            helper._sweep_orphan_tabs()   # 不得拋出

    def test_get_target_still_opens_tab_when_sweep_blows_up(self):
        with patch.object(helper, "_sweep_orphan_tabs", side_effect=OSError("boom")), \
             patch.object(helper, "_open_blank_tab", return_value=_tab("N")):
            self.assertEqual(helper.get_target("ORCL", "options"), ("N", "ws://N"))


class TestExitHandlers(_TabStateMixin, unittest.TestCase):

    def test_sigterm_becomes_system_exit_so_atexit_runs(self):
        """TimedCapture 逾時先送 TERM；Python 預設直接死、不跑 atexit，分頁就留著。"""
        original = signal.getsignal(signal.SIGTERM)
        try:
            with patch.object(helper.atexit, "register"):
                helper._EXIT_HANDLERS_INSTALLED = False
                helper._install_exit_handlers()
            handler = signal.getsignal(signal.SIGTERM)
            with self.assertRaises(SystemExit):
                handler(signal.SIGTERM, None)
        finally:
            signal.signal(signal.SIGTERM, original)
            helper._EXIT_HANDLERS_INSTALLED = False


class TestTabLifecycleInSubprocess(unittest.TestCase):
    """
    真的開一個子程序跑 cdp_helper，對它送 SIGTERM，確認 atexit 有把分頁關掉。
    CDP 端點用本機假伺服器代替，記下收到的 /json/new 與 /json/close。
    """

    def test_sigterm_closes_the_tab(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "requests.log"
            script = textwrap.dedent(f"""
                import http.server, threading, json, sys, time
                sys.path.insert(0, {str(Path(__file__).parent)!r})
                log = open({str(log)!r}, "a", buffering=1)
                class H(http.server.BaseHTTPRequestHandler):
                    def _reply(self):
                        log.write(self.command + " " + self.path + "\\n")
                        body = json.dumps({{"id": "T1", "type": "page", "url": "about:blank",
                                            "webSocketDebuggerUrl": "ws://T1"}}).encode()
                        self.send_response(200); self.end_headers(); self.wfile.write(body)
                    do_GET = do_PUT = _reply
                    def log_message(self, *a): pass
                srv = http.server.HTTPServer(("127.0.0.1", 0), H)
                threading.Thread(target=srv.serve_forever, daemon=True).start()
                import cdp_helper
                cdp_helper.CDP_BASE = "http://127.0.0.1:%d" % srv.server_port
                cdp_helper.TAB_TRACK_DIR = __import__("pathlib").Path({tmp!r}) / "tabs"
                cdp_helper.get_target("ORCL", "options")
                print("READY", flush=True)
                time.sleep(30)
            """)
            proc = subprocess.Popen([sys.executable, "-c", script], stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(proc.stdout.readline().strip(), "READY")
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=10)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
                proc.stdout.close()
            lines = log.read_text().splitlines()
            self.assertIn("PUT /json/new?about:blank", lines)
            self.assertIn("GET /json/close/T1", lines)
            self.assertEqual(list((Path(tmp) / "tabs").iterdir()), [])


class TestPreparePage(_TabStateMixin, unittest.TestCase):

    def test_navigates_the_dedicated_tab_to_the_target_url(self):
        nav = AsyncMock()
        with patch.object(helper, "get_target", return_value=("N", "ws://N")), \
             patch.object(helper, "activate_target", new=AsyncMock()), \
             patch.object(helper, "cdp_navigate", new=nav), \
             patch.object(helper.asyncio, "sleep", new=AsyncMock()):
            result = _run(helper.prepare_page("ORCL", "options", settle_ms=500))
        self.assertEqual(result, ("N", "ws://N"))
        nav.assert_awaited_once_with("ws://N", "https://www.barchart.com/stocks/quotes/ORCL/options",
                                     settle_ms=500)


class TestOpenBlankTab(unittest.TestCase):

    def test_uses_put_on_json_new(self):
        """Chrome 111 起 /json/new 只接受 PUT，GET 會回 405。"""
        response = unittest.mock.MagicMock()
        response.read.return_value = b'{"id": "N", "type": "page", "url": "about:blank", "webSocketDebuggerUrl": "ws://N"}'
        with patch.object(helper.urllib.request, "urlopen", return_value=response) as urlopen:
            tab = helper._open_blank_tab()

        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_method(), "PUT")
        self.assertEqual(request.full_url, f"{helper.CDP_BASE}/json/new?about:blank")
        self.assertEqual(tab["id"], "N")


if __name__ == "__main__":
    unittest.main(verbosity=2)
