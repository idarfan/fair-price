"""
Barchart Bull Call Vertical Spread (BCVS) 試算工具 — Stage 2: 指定履約日的
Call 鏈抓取。

bcvs.md §功能流程 步驟2：導覽指定 expiration 的 options 頁，解析 Call 側每個
strike 的完整 Barchart 欄位（strike/moneyness/bid/mid/ask/last/change/
pct_change/volume/open_interest/oi_change/iv/delta），跟頁面呈現一致，缺欄位
回 null，不得造值。bid/ask 過濾留給 Ruby（BcvsCacheService），這裡只管 DOM
原始值。

以 bpus_put_chain_scraper.py 為底，僅將篩選條件從 optionType==='Put' 改為
optionType==='Call'，其餘選擇器與流程逐字沿用（同一頁面結構，已實測驗證），
直連 CDP 9222。

Usage:  python3 bcvs_call_chain_scraper.py SYMBOL EXPIRATION

EXPIRATION 為 Barchart 原始 value（例如 "2026-08-21-m"，來自
bcvs_expirations_scraper.py 的輸出）。

Output JSON (stdout):
  success       -> {"status":"success","rows":[...],"underlying_price":N,"debug_url":"..."}
  no_candidates -> {"status":"no_candidates"}   # grid 空/讀不到（穩定性確認後仍空）
  expired       -> {"status":"barchart_session_expired"}
  error         -> {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH     = "options"
STAGE1_SETTLE   = 500
OPTIONS_SETTLE  = 1500
GRID_MAX_WAIT_S = 30

# Stage 2: 指定 expiration 的 Call 側全履約價。帶 view=sbs 後頁面會同時掛 3 個
# bc-data-grid（Call / Put / 第三個 type 為 null），Call 資料在其中一個，順序
# 不保證——因此不能只抓 document.querySelector 的第一個，要掃全部 grid 再用
# optionType 篩選 Call（沿用 bpus_put_chain_scraper.py 已實測驗證的做法）。
CALL_CHAIN_JS = """
(() => {
  const grids = [...document.querySelectorAll('bc-data-grid')];
  const rows = grids.flatMap(g => (g._data || []).map(r => r.raw || r));
  if (!grids.length || !grids.some(g => g._data)) return null;
  return rows.filter(r=>r.optionType==='Call'||r.symbolType==='Call')
    .map(r=>({
      expiration_date: r.expirationDate||r.expirationDateString||null,
      dte: typeof r.daysToExpiration==='number'?r.daysToExpiration:null,
      strike: r.strikePrice,
      moneyness: typeof r.moneyness==='number'?r.moneyness:null,
      bid: typeof r.bidPrice==='number'?r.bidPrice:null,
      mid: typeof r.midpoint==='number'?r.midpoint:null,
      ask: typeof r.askPrice==='number'?r.askPrice:null,
      last: typeof r.lastPrice==='number'?r.lastPrice:null,
      change: typeof r.priceChange==='number'?r.priceChange:null,
      pct_change: typeof r.percentChange==='number'?r.percentChange:null,
      volume: typeof r.volume==='number'?r.volume:null,
      open_interest: typeof r.openInterest==='number'?r.openInterest:null,
      oi_change: typeof r.openInterestChange==='number'?r.openInterestChange:(typeof r.oiChange==='number'?r.oiChange:null),
      iv: typeof r.volatility==='number'?r.volatility:null,
      delta: typeof r.delta==='number'?r.delta:null,
    }));
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


async def _wait_for_grid(ws_url, js_expr, max_wait_s=30, poll_s=0.5):
    """Poll for bc-data-grid._data to be non-null after navigation."""
    deadline = asyncio.get_event_loop().time() + max_wait_s
    while asyncio.get_event_loop().time() < deadline:
        result = await cdp_eval(ws_url, js_expr)
        if result is not None:
            return result
        await asyncio.sleep(poll_s)
    return None


async def _confirm_empty(ws_url, js_expr, delay_s=1.5):
    """Stability check: re-evaluate after delay_s to confirm [] is real, not mid-load."""
    await asyncio.sleep(delay_s)
    return await cdp_eval(ws_url, js_expr)


def _fill_exp_date(rows, exp_key):
    for r in rows:
        if not r.get("expiration_date"):
            r["expiration_date"] = exp_key


async def main(symbol, expiration):
    symbol = symbol.upper()

    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=STAGE1_SETTLE)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    exp_key = expiration[:10]  # "2026-08-21" from "2026-08-21-m"/"-w"
    chain_url = (
        f"https://www.barchart.com/stocks/quotes/{symbol}/options"
        f"?view=sbs&expiration={expiration}&moneyness=100"
    )
    await cdp_navigate(ws_url, chain_url, settle_ms=OPTIONS_SETTLE)
    await activate_target(target_id)

    rows = await _wait_for_grid(ws_url, CALL_CHAIN_JS, max_wait_s=GRID_MAX_WAIT_S)

    if rows is None:
        is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
        if is_expired:
            print(json.dumps({"status": "barchart_session_expired"}))
        else:
            print(json.dumps({"status": "error", "error": "grid did not load within timeout"}))
        return

    if not rows:
        confirmed = await _confirm_empty(ws_url, CALL_CHAIN_JS)
        if confirmed:
            rows = confirmed
        elif confirmed is None:
            is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
            if is_expired:
                print(json.dumps({"status": "barchart_session_expired"}))
            else:
                print(json.dumps({"status": "error", "error": "grid did not load within timeout"}))
            return
        else:
            print(json.dumps({"status": "no_candidates"}))
            return

    underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)
    if underlying_price is None:
        await asyncio.sleep(1.0)
        underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)

    _fill_exp_date(rows, exp_key)

    print(json.dumps({
        "status":             "success",
        "rows":               rows,
        "underlying_price":   underlying_price,
        "debug_url":          chain_url,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "RKLB"
    exp = sys.argv[2] if len(sys.argv) > 2 else ""
    asyncio.run(main(sym, exp))
