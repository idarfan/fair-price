"""
Barchart Bull Call Vertical Spread (BCVS) 試算工具 — Stage 1: 履約日清單抓取
＋標的摘要五值。

bcvs.md §功能流程 步驟1：回傳原始 expiration 清單（字串陣列，Barchart 原始
value，例如 "2026-08-21-m"）與現價；DTE / 顯示用 label 由 Rails 端計算。
v4 新增標的摘要：現價與漲跌、Latest Earnings（含 BMO/AMC）、Implied
Volatility (ATM)、Historic Volatility、IV Rank——這五個值不在 options
頁面本身，沿用 bpus_volatility_scraper.py 已實測驗證的
volatility-charts 頁 toolbar 選擇器（第二段導覽抓取，跟履約日清單分開，
任一段失敗不影響另一段——摘要抓不到就是 null，不阻塞主流程）。

履約日清單頁面結構與 Call/Put 無關（同一個 expiration dropdown），選擇器
逐字沿用 bpus_expirations_scraper.py（已實測驗證），直連 CDP 9222。

Usage:  python3 bcvs_expirations_scraper.py SYMBOL

Output JSON (stdout):
  success       -> {"status":"success","expirations":[...],"underlying_price":N,
                     "summary":{"price_change":N,"iv_atm":N,"hv":N,"iv_rank":N,
                     "latest_earnings":"..."},"debug_url":"..."}
  no_candidates -> {"status":"no_candidates"}   # expiration dropdown 空/讀不到
  expired       -> {"status":"barchart_session_expired"}
  error         -> {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH     = "options"
VOLATILITY_PATH = "volatility-charts"
STAGE1_SETTLE   = 3000
VOL_SETTLE      = 1500
VOL_MAX_WAIT_S  = 15

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

# UNDERLYING_JS 額外嘗試從同一個 rootScope 物件抓 change/percentChange——與
# underlying_price 同源（避免多一次 DOM 查詢），抓不到就是 null 不造值。
UNDERLYING_JS = """
(() => {
  try {
    const root = angular.element(
      document.querySelector('[ng-app]') || document.body
    ).scope().$root;
    for (const key of Object.keys(root)) {
      const v = root[key];
      if (v && typeof v === 'object') {
        if (typeof v.last === 'number' && v.last > 0) {
          return { price: v.last, change: typeof v.priceChange === 'number' ? v.priceChange : null };
        }
        if (typeof v.lastPrice === 'number' && v.lastPrice > 0) {
          return { price: v.lastPrice, change: typeof v.priceChange === 'number' ? v.priceChange : null };
        }
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
  return { price: Math.round(prices[Math.floor(prices.length / 2)] * 100) / 100, change: null };
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

# 沿用 bpus_volatility_scraper.py 已實測驗證的 toolbar 選擇器（同一個
# volatility-charts 頁，5 個 .item 呈現 Latest Earnings / IV / HV / IV Rank /
# IV Percentile，數值在 .item strong 裡）。
TOOLBAR_JS = """
(() => {
  const toolbar = document.querySelector('.bc-options-toolbar.volatility .bc-options-toolbar__second-row.with-earnings');
  if (!toolbar) return null;
  const items = [...toolbar.querySelectorAll('.item')];
  function findVal(labelSubstr) {
    const it = items.find(i => i.textContent.replace(/\\s+/g,' ').includes(labelSubstr));
    if (!it) return null;
    const strong = it.querySelector('strong');
    return strong ? strong.textContent.replace(/\\s+/g,' ').trim() : null;
  }
  return {
    latest_earnings: findVal('Earnings'),
    iv:              findVal('Implied Volatility'),
    hv:              findVal('Historic Volatility'),
    iv_rank:         findVal('IV Rank'),
  };
})()
"""


def _to_pct(raw):
    if not raw:
        return None
    m = re.search(r"[-+]?\d+(\.\d+)?", raw)
    return float(m.group(0)) if m else None


async def _wait_for_toolbar(ws_url, max_wait_s=VOL_MAX_WAIT_S, poll_s=0.5):
    deadline = asyncio.get_event_loop().time() + max_wait_s
    while asyncio.get_event_loop().time() < deadline:
        result = await cdp_eval(ws_url, TOOLBAR_JS)
        if result is not None:
            return result
        await asyncio.sleep(poll_s)
    return None


async def _fetch_summary(target_id, ws_url, symbol):
    """第二段導覽：volatility-charts 頁 toolbar 五值。失敗不影響第一段結果，
    呼叫端只需視為選配資料——回傳全 null 的 dict，不 raise。"""
    empty = {"iv_atm": None, "hv": None, "iv_rank": None, "latest_earnings": None}
    try:
        vol_url = f"https://www.barchart.com/stocks/quotes/{symbol}/{VOLATILITY_PATH}"
        await cdp_navigate(ws_url, vol_url, settle_ms=VOL_SETTLE)
        await activate_target(target_id)
        data = await _wait_for_toolbar(ws_url)
        if data is None:
            return empty
        return {
            "iv_atm":          _to_pct(data.get("iv")),
            "hv":              _to_pct(data.get("hv")),
            "iv_rank":         _to_pct(data.get("iv_rank")),
            "latest_earnings": data.get("latest_earnings"),
        }
    except Exception:
        return empty


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

    underlying = None
    for _ in range(3):
        underlying = await cdp_eval(ws_url, UNDERLYING_JS)
        if underlying is not None:
            break
        await asyncio.sleep(1.0)

    underlying_price = underlying.get("price") if underlying else None
    price_change = underlying.get("change") if underlying else None

    summary = await _fetch_summary(target_id, ws_url, symbol)
    summary["price_change"] = price_change

    print(json.dumps({
        "status":            "success",
        "expirations":       expirations,
        "underlying_price":  underlying_price,
        "summary":           summary,
        "debug_url":         options_url,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "RKLB"
    asyncio.run(main(sym))
