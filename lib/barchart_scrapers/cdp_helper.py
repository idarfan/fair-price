"""
Minimal CDP helper using direct WebSocket (no Playwright dependency)
Reused by all three Barchart scrapers.

Key: Windows Chrome suspends background tabs. Always call activate_target()
before eval to wake the tab from suspension.
"""
import asyncio
import json
import urllib.request
import websockets

CDP_BASE = "http://127.0.0.1:9222"


def get_target(symbol, page_type):
    """Return (target_id, ws_url) for the matching page, or any barchart page as fallback."""
    targets = json.loads(
        urllib.request.urlopen(f"{CDP_BASE}/json", timeout=5).read()
    )
    pattern = f"barchart.com/stocks/quotes/{symbol}/{page_type}"
    # Exact match first
    for t in targets:
        if t.get("type") == "page" and pattern in t.get("url", ""):
            return t["id"], t["webSocketDebuggerUrl"]
    # Fallback: any barchart page (we'll navigate it)
    for t in targets:
        if t.get("type") == "page" and "barchart.com" in t.get("url", ""):
            return t["id"], t["webSocketDebuggerUrl"]
    return None, None


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


async def cdp_eval(ws_url, js_expr, timeout=25):
    """Evaluate JavaScript in a CDP page and return the result value."""
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
    Find or fallback to a barchart tab, activate it, navigate if needed.
    Returns (target_id, ws_url).
    """
    target_id, ws_url = get_target(symbol, page_type)
    if not target_id:
        return None, None

    # Activate first (un-suspend the tab); Chrome needs ~1s to fully wake
    await activate_target(target_id)
    await asyncio.sleep(1.5)

    target_url = f"https://www.barchart.com/stocks/quotes/{symbol}/{page_type}"
    page_type_path = f"/{page_type}"

    # Check current URL; navigate only if needed
    try:
        current_url = await cdp_eval(ws_url, "window.location.href", timeout=10)
    except TimeoutError:
        current_url = ""

    if page_type_path not in (current_url or ""):
        await cdp_navigate(ws_url, target_url, settle_ms=settle_ms)
        # Re-activate after navigation (Chrome may have focused elsewhere)
        await activate_target(target_id)

    return target_id, ws_url
