"""
LEAPS 垂直價差 — Stage 1：到期日清單抓取（leaps-call-spread-spec P1）。

2026-09-25 自 bcvs_expirations_scraper.py 複製（使用者裁示：垂直價差不碰 bcvs，
sidecar 各自一份）。選擇器逐字沿用 bcvs／bpus 已實測驗證的版本；不抓 bcvs 的
volatility 摘要（垂直價差用不到）。另加「讀不到到期日」的原因判定（P0 第 13 步
實測 ZZZZQ／BRK.A），只讀 DOM。直連 CDP 9222。

Usage:  python3 leaps_spread_expirations_scraper.py SYMBOL

Output JSON (stdout):
  success          -> {"status":"success","expirations":[...],"underlying_price":N,"debug_url":"..."}
  symbol_not_found -> {"status":"symbol_not_found"}   # 404 頁（.bc-error-404-page）
  no_options       -> {"status":"no_options"}         # 頁面正常但 "no option data"
  no_candidates    -> {"status":"no_candidates"}      # 其他讀不到到期日的情況
  expired          -> {"status":"barchart_session_expired"}
  error            -> {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH   = "options"
STAGE1_SETTLE = 3000

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

# 讀不到到期日時分辨原因。innerText 對隱藏元素是空字串，ng-hide 的 .error-page 不會誤判。
PAGE_STATE_JS = """
(() => {
  if (document.querySelector('.bc-error-404-page')) return 'not_found';
  const noData = [...document.querySelectorAll('.error-page')]
    .some(e => /no option data/i.test(e.innerText || ''));
  return noData ? 'no_options' : null;
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

    if await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    expirations = []
    for _ in range(8):
        expirations = await cdp_eval(ws_url, EXPIRATIONS_JS) or []
        if expirations:
            break
        await asyncio.sleep(1.0)

    if not expirations:
        if await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False:
            print(json.dumps({"status": "barchart_session_expired"}))
            return
        page_state = await cdp_eval(ws_url, PAGE_STATE_JS)
        status = {"not_found": "symbol_not_found", "no_options": "no_options"}.get(page_state, "no_candidates")
        print(json.dumps({"status": status}))
        return

    underlying = None
    for _ in range(3):
        underlying = await cdp_eval(ws_url, UNDERLYING_JS)
        if underlying is not None:
            break
        await asyncio.sleep(1.0)

    print(json.dumps({
        "status":           "success",
        "expirations":      expirations,
        "underlying_price": underlying,
        "debug_url":        options_url,
    }))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "error": "Usage: leaps_spread_expirations_scraper.py SYMBOL"}))
        sys.exit(1)
    try:
        asyncio.run(main(sys.argv[1]))
    except Exception as e:  # noqa: BLE001 — sidecar 一律以 JSON 回報錯誤
        import traceback
        print(json.dumps({"status": "error", "error": str(e), "traceback": traceback.format_exc()}))
