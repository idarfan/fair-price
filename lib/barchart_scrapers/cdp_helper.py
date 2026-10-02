"""
Minimal CDP helper using direct WebSocket (no Playwright dependency)
Reused by all three Barchart scrapers.

Key: Windows Chrome suspends background tabs. Always call activate_target()
before eval to wake the tab from suspension.
"""
import asyncio
import atexit
import json
import signal
import sys
import time
import urllib.request
from pathlib import Path

import websockets

CDP_BASE = "http://127.0.0.1:9222"

# 每次抓取開自己的專屬分頁（2026-10-01）。原本借用任一 Barchart 分頁再導航，
# 兩個不同代號的抓取同時進行時會搶到同一個分頁、把對方導航走——失敗，
# 或讀到別的代號的資料。
#
# 分頁要在爬蟲結束時關掉：正常結束與例外走 atexit；TimedCapture 逾時先送
# SIGTERM，Python 預設直接死、不跑 atexit，所以把 SIGTERM 轉成 SystemExit。
# SIGKILL 誰都攔不到，靠追蹤檔：每開一個分頁寫一個檔，下次開分頁前把
# 超過 ORPHAN_AGE_S 的關掉。
TAB_TRACK_DIR = Path(__file__).resolve().parents[2] / "tmp" / "cdp_tabs"
# LEAPS 爬蟲沒有外層時限、實測 3–5 分鐘；不能把還在跑的分頁當孤兒關掉。
ORPHAN_AGE_S = 30 * 60

_OWNED_TABS = []
_EXIT_HANDLERS_INSTALLED = False


def _list_targets():
    return json.loads(
        urllib.request.urlopen(f"{CDP_BASE}/json", timeout=5).read()
    )


def _open_blank_tab():
    """Open a new about:blank tab (Chrome 111+ only accepts PUT on /json/new)."""
    request = urllib.request.Request(f"{CDP_BASE}/json/new?about:blank", method="PUT")
    return json.loads(urllib.request.urlopen(request, timeout=5).read())


def _close_tab(target_id):
    urllib.request.urlopen(f"{CDP_BASE}/json/close/{target_id}", timeout=5).read()


def _forget_tab(target_id):
    try:
        (TAB_TRACK_DIR / target_id).unlink()
    except OSError:
        pass   # 已經不在、權限、或根本不是檔案——追蹤檔只是保險，不能讓抓取失敗


def close_owned_tabs():
    """關掉本程序開過的分頁。一個關不掉（已被關、Chrome 斷線）不影響其他的。"""
    while _OWNED_TABS:
        target_id = _OWNED_TABS.pop(0)
        try:
            _close_tab(target_id)
        except (OSError, ValueError):
            pass
        _forget_tab(target_id)


def _sweep_orphan_tabs():
    """
    關掉被 SIGKILL 的爬蟲留下的分頁（追蹤檔超過 ORPHAN_AGE_S）。

    追蹤目錄是共用位置，裡面可能出現別人放的東西（2026-10-01：hook 建了 .claude/
    資料夾，滿 30 分鐘後 unlink 一個資料夾丟 IsADirectoryError，**所有爬蟲**每次都失敗）。
    所以只處理一般檔案、任何錯誤都吞掉——清理只是保險，絕不能讓抓取失敗。
    """
    try:
        entries = list(TAB_TRACK_DIR.iterdir()) if TAB_TRACK_DIR.is_dir() else []
    except OSError:
        return
    cutoff = time.time() - ORPHAN_AGE_S
    for entry in entries:
        try:
            if not entry.is_file() or entry.stat().st_mtime >= cutoff:
                continue
            try:
                _close_tab(entry.name)
            except (OSError, ValueError):
                pass   # 分頁早就不在了也一樣要清追蹤檔
            _forget_tab(entry.name)
        except Exception as e:   # noqa: BLE001 — 見上：清理失敗不能變成抓取失敗
            print(f"[cdp_helper] orphan sweep skipped {entry.name}: {e}", file=sys.stderr)


def _exit_on_sigterm(signum, frame):
    sys.exit(128 + signum)


def _install_exit_handlers():
    """冪等：每次開分頁都呼叫，只有第一次真的安裝。"""
    global _EXIT_HANDLERS_INSTALLED
    if _EXIT_HANDLERS_INSTALLED:
        return
    atexit.register(close_owned_tabs)
    signal.signal(signal.SIGTERM, _exit_on_sigterm)
    _EXIT_HANDLERS_INSTALLED = True


def get_target(symbol, page_type):
    """
    開一個本次抓取專屬的分頁，回 (target_id, ws_url)；開不了回 (None, None)。
    不看既有分頁——借用別人的分頁正是並行抓取互相干擾的原因。
    symbol／page_type 保留在簽名上給呼叫端，導航由 prepare_page 負責。
    """
    try:
        _sweep_orphan_tabs()
    except Exception as e:   # noqa: BLE001 — 清理是保險，失敗不能擋住這次抓取
        print(f"[cdp_helper] orphan sweep failed: {e}", file=sys.stderr)
    try:
        tab = _open_blank_tab()
    except (OSError, ValueError):
        return None, None

    target_id = tab["id"]
    _install_exit_handlers()
    _OWNED_TABS.append(target_id)
    try:
        TAB_TRACK_DIR.mkdir(parents=True, exist_ok=True)
        (TAB_TRACK_DIR / target_id).write_text(f"{symbol} {page_type}")
    except OSError:
        pass   # 追蹤檔只是 SIGKILL 的保險，寫不了不能讓抓取失敗
    return target_id, tab["webSocketDebuggerUrl"]


def get_browser_ws():
    """Return browser-level WebSocket URL."""
    version = json.loads(
        urllib.request.urlopen(f"{CDP_BASE}/json/version", timeout=5).read()
    )
    return version["webSocketDebuggerUrl"]


async def activate_target(target_id):
    """Bring a tab to foreground so Chrome un-suspends its JS engine."""
    browser_ws = get_browser_ws()
    async with websockets.connect(browser_ws, open_timeout=10) as ws:
        await ws.send(json.dumps({
            "id": 1,
            "method": "Target.activateTarget",
            "params": {"targetId": target_id},
        }))
        try:
            await asyncio.wait_for(ws.recv(), timeout=5)
        except asyncio.TimeoutError:
            pass  # activation is best-effort


async def cdp_eval(ws_url, js_expr, timeout=25, target_id=None, attempts=2):
    """
    Evaluate JavaScript in a CDP page and return the result value.

    Windows Chrome freezes background tabs: while frozen the renderer never
    answers Runtime.evaluate, so a single eval can burn the whole timeout even
    though CDP itself is healthy. When target_id is supplied we re-activate the
    tab (which un-freezes the renderer) and try again before giving up — that
    turns the common "tab went to sleep mid-scrape" case from a hard failure
    into a 1-2 second hiccup.
    """
    last_error = None
    for attempt in range(max(1, attempts)):
        if attempt and target_id:
            await activate_target(target_id)
            await asyncio.sleep(1.0)
        try:
            return await _cdp_eval_once(ws_url, js_expr, timeout)
        except (TimeoutError, asyncio.TimeoutError) as e:
            last_error = e
            if not target_id:
                break
    raise last_error


async def _cdp_eval_once(ws_url, js_expr, timeout):
    async with websockets.connect(ws_url, open_timeout=10, max_size=10_000_000) as ws:
        msg_id = 1
        await ws.send(json.dumps({
            "id": msg_id,
            "method": "Runtime.evaluate",
            "params": {
                "expression": js_expr,
                "returnByValue": True,
                "awaitPromise": False,
            },
        }))
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=2.0)
                resp = json.loads(raw)
                if resp.get("id") == msg_id:
                    r = resp.get("result", {})
                    if "exceptionDetails" in r:
                        raise RuntimeError(str(r["exceptionDetails"]))
                    return r.get("result", {}).get("value")
            except asyncio.TimeoutError:
                continue
        raise TimeoutError("CDP eval timed out")


async def cdp_navigate(ws_url, target_url, settle_ms=6000):
    """Navigate an existing CDP page to target_url and wait settle_ms for JS to render."""
    async with websockets.connect(ws_url, open_timeout=10) as ws:
        msg_id = 1
        await ws.send(json.dumps({
            "id": msg_id,
            "method": "Page.navigate",
            "params": {"url": target_url},
        }))
        deadline = asyncio.get_event_loop().time() + 30
        while asyncio.get_event_loop().time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=2.0)
                if json.loads(raw).get("id") == msg_id:
                    break
            except asyncio.TimeoutError:
                continue
    await asyncio.sleep(settle_ms / 1000)


async def prepare_page(symbol, page_type, settle_ms):
    """
    開專屬分頁並導航到目標頁，回 (target_id, ws_url)。
    分頁一律是新開的 about:blank，所以一定要導航（沿用原本「網址不對就導航」那條路徑，
    等待時機不變）。分頁在爬蟲結束時由 close_owned_tabs 關掉。
    """
    target_id, ws_url = get_target(symbol, page_type)
    if not target_id:
        return None, None

    # Activate first (un-suspend the tab); Chrome needs ~1s to fully wake
    await activate_target(target_id)
    await asyncio.sleep(1.5)

    target_url = f"https://www.barchart.com/stocks/quotes/{symbol}/{page_type}"
    await cdp_navigate(ws_url, target_url, settle_ms=settle_ms)
    # Re-activate after navigation (Chrome may have focused elsewhere)
    await activate_target(target_id)

    return target_id, ws_url
