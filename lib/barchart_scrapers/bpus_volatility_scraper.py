"""
Barchart Bull Put Spread (BPUS) 三級試算工具 — Volatility 背景資料抓取。

bpus-fix.md 項目6：在保守/激進收租分頁下方補一段目前波動率對策略的影響說明，
背景執行不阻塞主流程（履約日/Put 鏈抓取）。禁止用 Barchart 內部 API，改用
Playwright/CDP 讀 DOM——沿用 bpus_put_chain_scraper.py 同一套 cdp_helper 直連
CDP 9222 的做法。

實測(2026-07-14, RKLB, https://www.barchart.com/stocks/quotes/RKLB/volatility-charts)：
頁面用 .bc-options-toolbar.volatility .bc-options-toolbar__second-row.with-earnings
下的 5 個 .item 呈現 Latest Earnings / Implied Volatility(IV) / Historic
Volatility(HV) / IV Rank / IV Percentile，數值都在 .item strong 裡。這幾個
數字是「最近 30 天期」整體指標，不隨 URL 的 expiration 參數變動（只影響上方
Term Structure 圖表的標記點），此腳本仍原樣帶入 expiration 參數以符合規格
URL 格式，但抓取的是頁面級 toolbar 數字。

Usage:  python3 bpus_volatility_scraper.py SYMBOL EXPIRATION

Output JSON (stdout):
  success       -> {"status":"success","iv":N,"hv":N,"iv_rank":N,"iv_percentile":N,
                     "latest_earnings":"...","debug_url":"..."}
  no_candidates -> {"status":"no_candidates"}   # toolbar 讀不到（穩定性確認後仍空）
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

TARGET_PATH   = "volatility-charts"
STAGE1_SETTLE = 500
PAGE_SETTLE   = 1500
MAX_WAIT_S    = 20

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
    iv_percentile:   findVal('IV Percentile'),
  };
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


def _to_pct(raw):
    if not raw:
        return None
    m = re.search(r"[-+]?\d+(\.\d+)?", raw)
    return float(m.group(0)) if m else None


async def _wait_for_toolbar(ws_url, max_wait_s=MAX_WAIT_S, poll_s=0.5):
    deadline = asyncio.get_event_loop().time() + max_wait_s
    while asyncio.get_event_loop().time() < deadline:
        result = await cdp_eval(ws_url, TOOLBAR_JS)
        if result is not None:
            return result
        await asyncio.sleep(poll_s)
    return None


async def main(symbol, expiration):
    symbol = symbol.upper()

    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=STAGE1_SETTLE)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    vol_url = f"https://www.barchart.com/stocks/quotes/{symbol}/{TARGET_PATH}"
    if expiration:
        vol_url += f"?expiration={expiration}"
    await cdp_navigate(ws_url, vol_url, settle_ms=PAGE_SETTLE)
    await activate_target(target_id)

    data = await _wait_for_toolbar(ws_url)

    if data is None:
        is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
        if is_expired:
            print(json.dumps({"status": "barchart_session_expired"}))
        else:
            print(json.dumps({"status": "no_candidates"}))
        return

    print(json.dumps({
        "status":          "success",
        "iv":              _to_pct(data.get("iv")),
        "hv":              _to_pct(data.get("hv")),
        "iv_rank":         _to_pct(data.get("iv_rank")),
        "iv_percentile":   _to_pct(data.get("iv_percentile")),
        "latest_earnings": data.get("latest_earnings"),
        "debug_url":       vol_url,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "RKLB"
    exp = sys.argv[2] if len(sys.argv) > 2 else ""
    asyncio.run(main(sym, exp))
