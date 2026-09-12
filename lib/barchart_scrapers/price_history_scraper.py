"""
Barchart 日線 OHLCV scraper — CDP direct WebSocket, no Playwright.

用途：結構型 POI（FVG／缺口／Order Block／供需區）與「當日區間」卡需要逐根 K 棒。
VOLAP 只給分箱統計、沒有 K 棒；interactive-chart 主圖 plot 的 record.storage
實測是空 Map，也撈不到——所以得另外抓這一頁。

頁面路徑是 **price-history/historical**，不是 price-history/daily
（後者是 404，頁面標題會變成 "Page not found"）。

資料在 `bc-data-grid._data`：**它本身就是列陣列**，不是 `._data.raw`
（options_flow_scraper 讀的是 `._data.raw`，兩頁不一樣，不要照抄）。
每一列的屬性是 getter，JSON.stringify 會得到 `{}`，必須逐欄取值；
`row.raw` 才有型別正確的值（ISO 日期字串 + 數字），畫面用的 row.xxx 是
帶千分位的字串。

⚠️ 這一頁只給約 3 個月（實測 SHOP 64 根）。頁面說明寫著日線最多可回溯兩年，
但區間控制在 Historical Data Download 頁（CSV），這支不處理。
呼叫端請看 payload 的 bars_count，不要假設有 252 根。

Usage: python3 price_history_scraper.py SHOP
Output: JSON to stdout
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, activate_target


TARGET_PATH = "price-history/historical"

POLL_INTERVAL_S = 3
POLL_TIMEOUT_S  = 45

# 格線還在建的中間狀態，要繼續等，不是錯誤。
TRANSIENT_STATES = {"no_grid", "no_data", "empty"}

EXTRACT_JS = r"""
(() => {
  if (window.bcIsLoggedIn === false) return {state: 'logged_out'};
  const g = document.querySelector('bc-data-grid');
  if (!g) return {state: 'no_grid'};
  if (!g._data) return {state: 'no_data'};
  const list = Array.from(g._data);
  if (!list.length) return {state: 'empty'};

  const bars = [];
  for (const row of list) {
    const r = row && row.raw;
    if (!r) continue;
    // 任何一個價格缺值就整根丟掉——寧可少一根，也不要讓 0 假裝成價格
    // 混進 volume profile 與結構判斷裡。
    if (r.tradeTime == null || r.openPrice == null || r.highPrice == null ||
        r.lowPrice == null || r.lastPrice == null) continue;
    bars.push({
      bar_date: String(r.tradeTime),
      open: r.openPrice, high: r.highPrice, low: r.lowPrice, close: r.lastPrice,
      volume: r.volume == null ? null : r.volume
    });
  }
  return {state: bars.length ? 'ready' : 'empty', rows: list.length, bars: bars};
})()
"""


def fail(status, error=None):
    payload = {"status": status}
    if error:
        payload["error"] = str(error)[:300]
    print(json.dumps(payload))


async def main(symbol):
    target_id, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=8000)
    if not ws:
        fail("error", "No Chrome CDP page found")
        return

    deadline = asyncio.get_event_loop().time() + POLL_TIMEOUT_S
    data = None
    while True:
        r = await cdp_eval(ws, EXTRACT_JS, target_id=target_id)
        # 腳本一律回物件，None 只可能是整頁被換掉（例如被導去登入頁）。
        if r is None:
            fail("barchart_session_expired")
            return
        state = r.get("state")
        if state == "logged_out":
            fail("barchart_session_expired")
            return
        if state == "ready":
            data = r
            break
        if state not in TRANSIENT_STATES:
            fail("dom_structure_changed", "unexpected state: %s" % state)
            return
        if asyncio.get_event_loop().time() >= deadline:
            fail("dom_structure_changed",
                 "格線一直沒有資料（state=%s）——可能是頁面結構變了，"
                 "或這個代號沒有歷史資料" % state)
            return
        await activate_target(target_id)
        await asyncio.sleep(POLL_INTERVAL_S)

    bars = data["bars"]
    # 由舊到新排序：結構型 POI 的判斷（FVG 看連續三根、Order Block 看位移根
    # 之前那根）全部依賴時間正序。在這裡排好，呼叫端不要各自 reverse。
    bars.sort(key=lambda b: b["bar_date"])

    print(json.dumps({
        "status": "success",
        "symbol": symbol,
        "bars_count": len(bars),
        "first_date": bars[0]["bar_date"],
        "last_date": bars[-1]["bar_date"],
        "bars": bars,
    }))


if __name__ == "__main__":
    sym = sys.argv[1].upper() if len(sys.argv) > 1 else "SHOP"
    try:
        asyncio.run(main(sym))
    except Exception as e:
        fail("error", e)
