"""
Barchart Bull Call Vertical Spread (BCVS) 試算工具 — Stage 1: 履約日清單抓取。

bcvs.md §功能流程 步驟1：只回傳原始 expiration 清單（字串陣列，Barchart 原始
value，例如 "2026-08-21-m"）與現價；DTE / 顯示用 label 由 Rails 端計算。

履約日清單頁面結構與 Call/Put 無關（同一個 expiration dropdown），選擇器
逐字沿用 bpus_expirations_scraper.py（已實測驗證），直連 CDP 9222。

Usage:  python3 bcvs_expirations_scraper.py SYMBOL

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
