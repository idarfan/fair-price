"""
Barchart Bull Put Spread (BPUS) 三級試算工具 — Stage 1: 履約日清單抓取。

bpus.md §3.1：只回傳原始 expiration 清單（字串陣列，Barchart 原始 value，例如
"2026-08-21-m"）與現價；DTE / 顯示用 label 由 Rails 端計算（該規格明講）。

沿用 pmcc_short_call_scraper.py 的 EXPIRATIONS_JS / UNDERLYING_JS 選擇器
（同一頁面結構，已實測驗證），直連 CDP 9222（不經 9223 relay，理由見 bpus.md
規劃階段確認：本 repo 所有既有 scraper 都直連 9222，9223 是 playwright-mcp
專用中間層，跟這支 Python sidecar 無關）。

Usage:  python3 bpus_expirations_scraper.py SYMBOL

Output JSON (stdout):
  success       -> {"status":"success","expirations":[...],"underlying_price":N,"debug_url":"..."}
  no_candidates -> {"status":"no_candidates"}   # expiration dropdown 空/讀不到
  expired       -> {"status":"barchart_session_expired"}
  error         -> {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH   = "options"
STAGE1_SETTLE = 3000

# 沿用 pmcc_short_call_scraper.py 已實測驗證的選擇器（同一頁面結構）
EXPIRATIONS_JS = """
(() => {
  const sel = [...document.querySelectorAll('select')].find(
    s => s.className.includes('ng-') && s.options.length > 3 &&
         [...s.options].some(o => /\\d{4}-\\d{2}-\\d{2}/.test(o.value))
  );
  if (!sel) return null;
  return [...sel.options].map(o => o.value.trim()).filter(v => /\\d{4}-\\d{2}-\\d{2}/.test(v));
})()
"""

UNDERLYING_JS = """
(() => {
  try {
    const root = angular.element(
      document.querySelector('[ng-app]') || document.body
    ).scope().$root;
    for (const key of Object.keys(root)) {
      const v = root[key];
      if (v && typeof v === 'object') {
        if (typeof v.last === 'number' && v.last > 0) return v.last;
        if (typeof v.lastPrice === 'number' && v.lastPrice > 0) return v.lastPrice;
      }
    }
  } catch(e) {}
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  const prices = grid._data
    .map(r => r.raw || r)
    .filter(r => typeof r.moneyness === 'number' &&
                 r.moneyness > 0.05 && r.moneyness < 0.95 && r.strikePrice > 0)
    .map(r => r.strikePrice / (1 - r.moneyness));
  if (!prices.length) return null;
  prices.sort((a, b) => a - b);
  return Math.round(prices[Math.floor(prices.length / 2)] * 100) / 100;
})()
"""

SESSION_EXPIRED_JS = """
(() => {
  const modal = document.querySelector('div.bc-overlay-modal-wrapper');
  if (!modal) return false;
  const text = modal.innerText.trim().toLowerCase();
  return text.includes('sign in') || text.includes('log in') ||
         text.includes('welcome to barchart') || text.includes('continue with google');
})()
"""


async def main(symbol):
    symbol = symbol.upper()

    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=500)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    options_url = f"https://www.barchart.com/stocks/quotes/{symbol}/options"
    await cdp_navigate(ws_url, options_url, settle_ms=STAGE1_SETTLE)
    await activate_target(target_id)

    is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
    if is_expired:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    # 實測(2026-07-13, RKLB)：完整 reload 後單次固定 3 秒 settle 常常不夠——
    # t=4.0s 時 select 還是空的，t=5.3s 才填滿 15 個履約日。用短輪詢取代單次讀取，
    # 比拉長固定 sleep 更省時間又更穩（同一頁面 grid row 資料也有相同現象，見
    # bpus_put_chain_scraper.py 的 _wait_for_grid）。
    expirations = []
    for _ in range(8):
        expirations = await cdp_eval(ws_url, EXPIRATIONS_JS) or []
        if expirations:
            break
        await asyncio.sleep(1.0)

    if not expirations:
        is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
        if is_expired:
            print(json.dumps({"status": "barchart_session_expired"}))
        else:
            print(json.dumps({"status": "no_candidates"}))
        return

    # 現價來自 bc-data-grid 的 moneyness 反推（Angular rootScope 探測常在剛 reload
    # 完的頁面上抓不到 scope），grid row 資料常比 expiration 下拉選單晚一拍渲染完，
    # 實測(2026-07-13, RKLB)：緊接著 reload 後立刻讀會拿到 null，重試幾次即可。
    underlying_price = None
    for _ in range(3):
        underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)
        if underlying_price is not None:
            break
        await asyncio.sleep(1.0)

    print(json.dumps({
        "status":            "success",
        "expirations":       expirations,
        "underlying_price":  underlying_price,
        "debug_url":         options_url,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "RKLB"
    asyncio.run(main(sym))
