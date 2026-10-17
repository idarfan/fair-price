"""Barchart 期權合約日線收盤價（規格 P3b barchart_dom）— 只讀 DOM，不呼叫任何 Barchart API。

用法：barchart_option_history.py 'MSFT|20261016|340.00C' [--screenshot /abs/path.png]
輸出 JSON：
  {"status": "success", "url", "title", "rows": [{"date", "close", "underlying"}...]}
  {"status": "empty", ...}          頁面正確但格線 0 列（實測已到期合約即如此）→ 呼叫端改走 bs_model
  {"status": "wrong_page"|"barchart_session_expired"|"error", "error"}

頁面為 /stocks/quotes/{合約}/price-history/historical；資料在 bc-data-grid._data（列陣列），
每列 row.raw 為型別正確的值（tradeTime ISO 日期、lastPrice、volume、baseLastPrice）。實測約 3 個月。
⚠️ 2026-10-17 實測：當日無成交時 lastPrice=0（畫面 N/A），或 volume=null 而 lastPrice 沿用前一日價格
（畫面 Volume 顯示 0）。這兩種都不是當日收盤，由 Ruby 端（PremiumReference）判定排除；這裡原樣輸出。
格線在 shadow DOM 內，日期文字無法定位，截圖只證明頁面為該合約。
分頁管理（專屬分頁、結束時關閉）沿用 lib/barchart_scrapers/cdp_helper.py，唯讀引用不修改。
"""
import argparse
import asyncio
import base64
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "barchart_scrapers"))
from cdp_helper import activate_target, cdp_eval, close_owned_tabs, prepare_page  # noqa: E402

import websockets  # noqa: E402

TARGET_PATH = "price-history/historical"
SETTLE_MS = 8000
POLL_INTERVAL_S = 3
POLL_TIMEOUT_S = 30

EXTRACT_JS = r"""
(() => {
  if (window.bcIsLoggedIn === false) return {state: 'logged_out'};
  const g = document.querySelector('bc-data-grid');
  if (!g) return {state: 'no_grid', title: document.title, url: location.href};
  if (!g._data) return {state: 'no_data', title: document.title, url: location.href};
  const rows = [];
  for (const row of Array.from(g._data)) {
    const r = row && row.raw;
    if (!r || r.tradeTime == null || r.lastPrice == null) continue;
    rows.push({date: String(r.tradeTime), close: r.lastPrice, volume: r.volume == null ? 0 : r.volume,
               underlying: r.baseLastPrice == null ? null : r.baseLastPrice});
  }
  return {state: rows.length ? 'ready' : 'empty', title: document.title, url: location.href, rows: rows};
})()
"""


def expected_title_prefix(contract):
    """'MSFT|20261016|340.00C' → 'MSFT' 與 'Call'；用來確認頁面真的是這個合約。"""
    ticker, _, strike_right = contract.split("|")
    return ticker, ("Call" if strike_right.endswith("C") else "Put"), strike_right[:-1]


async def screenshot(ws_url, path):
    async with websockets.connect(ws_url, open_timeout=10, max_size=None) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Page.captureScreenshot", "params": {"format": "png"}}))
        while True:
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=20))
            if message.get("id") == 1:
                pathlib.Path(path).write_bytes(base64.b64decode(message["result"]["data"]))
                return


async def fetch(contract, screenshot_path):
    target_id, ws_url = await prepare_page(contract, TARGET_PATH, settle_ms=SETTLE_MS)
    if not ws_url:
        return {"status": "error", "error": "No Chrome CDP page found"}
    deadline = asyncio.get_event_loop().time() + POLL_TIMEOUT_S
    while True:
        result = await cdp_eval(ws_url, EXTRACT_JS, target_id=target_id)
        if result is None or result.get("state") == "logged_out":
            return {"status": "barchart_session_expired"}
        if result["state"] == "ready" or asyncio.get_event_loop().time() >= deadline:
            break
        await activate_target(target_id)
        await asyncio.sleep(POLL_INTERVAL_S)

    ticker, right, strike = expected_title_prefix(contract)
    title = result.get("title", "")
    if not (title.startswith(ticker) and right in title and strike in title):
        return {"status": "wrong_page", "error": f"title={title!r}", "url": result.get("url")}
    if screenshot_path:
        await screenshot(ws_url, screenshot_path)
    status = {"ready": "success", "empty": "empty"}.get(result["state"])
    if status is None:
        return {"status": "error", "error": f"格線未就緒（state={result['state']}）", "url": result.get("url")}
    return {"status": status, "url": result["url"], "title": title, "rows": result.get("rows", [])}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Barchart 期權合約日線收盤價（DOM）")
    parser.add_argument("contract")
    parser.add_argument("--screenshot")
    args = parser.parse_args(argv)
    try:
        payload = asyncio.run(fetch(args.contract, args.screenshot))
    except Exception as e:  # noqa: BLE001 — 一律以 JSON 回報，由 Ruby 端判斷
        payload = {"status": "error", "error": f"{type(e).__name__}: {e}"[:300]}
    finally:
        close_owned_tabs()
    json.dump(payload, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
