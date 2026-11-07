#!/usr/bin/env python3
"""
Barchart Options Overview History 爬蟲（leaps-iv-environment.md P2）

用法：python3 barchart_iv_history_scraper.py SYMBOL [latest|backfill]

  latest   — 切到 1M，只回最新一列（每次 LEAPS 查詢／每日排程用）
  backfill — 切到 2Y（P0 實測最長區間，2026-11-06 為 520 列），回整段

資料一律讀頁面 DOM（bc-data-grid._data），切換區間以點擊頁面 UI 完成，不呼叫任何 Barchart API。
Barchart 會記住上次選的區間（P0 偵察）：開始前記下原本的區間，結束前切回去，
不改動使用者帳號的顯示設定；也因此每次都要明確切換，不能假設預設 3M。

HV 不在 options-history 頁：讀 /overview 的「Historical Volatility」（P0 偵察）。

輸出（stdout JSON）：
  success → {"status":"success","mode":...,"rows":[raw...],"quote_date_text":"11/05/26",
             "source_url":...,"hv_pct":46.66,"hv_source_url":...,"period_label":"1M",
             "restored_period":"3M"}
  barchart_session_expired → {"status":"barchart_session_expired"}
  error → {"status":"error","error":"..."}
"""

import asyncio
import json
import sys

from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

PAGE_TYPE       = "options-history"
MODE_PERIODS    = {"latest": "1M", "backfill": "2Y"}
GRID_MAX_WAIT_S = 60
PERIOD_WAIT_S   = 45
POLL_S          = 1.5
STABLE_POLLS    = 3     # 連續幾次讀到相同的列數與首尾日期才算載入完成
MIN_SETTLE_S    = 6     # 區間未變（本來就是目標區間）時，至少等這麼久才採信

GRID_JS = """
(() => {
  const g = document.querySelector('bc-data-grid');
  if (!g || !g._data || !g._data.length) return null;
  return g._data.map(r => r.raw || r).map(r => ({
    date: r.date,
    weightedImpliedVolatility: r.weightedImpliedVolatility,
    weightedImpliedVolatilityChange: r.weightedImpliedVolatilityChange,
    impliedVolatilityRank1y: r.impliedVolatilityRank1y,
    impliedVolatilityPercentile1y: r.impliedVolatilityPercentile1y,
    putCallVolumeRatio: r.putCallVolumeRatio,
    totalVolume: r.totalVolume,
    putCallOpenInterestRatio: r.putCallOpenInterestRatio,
    totalOpenInterest: r.totalOpenInterest,
    historicalLastPrice: r.historicalLastPrice,
  }));
})()
"""

# 目前選中的區間（li.active）與可選清單
PERIOD_STATE_JS = """
(() => {
  const items = [...document.querySelectorAll('#bc-price-history-time-frame li')];
  if (!items.length) return null;
  const active = items.find(li => li.classList.contains('active'));
  return { active: active ? active.textContent.trim() : null,
           options: items.map(li => li.textContent.trim()) };
})()
"""

# 點擊頁面上的區間選項（Angular data-ng-click="changePeriod(item)"）
CLICK_PERIOD_JS = """
((label) => {
  const li = [...document.querySelectorAll('#bc-price-history-time-frame li')]
    .find(el => el.textContent.trim() === label);
  if (!li) return false;
  li.click();
  return true;
})(%s)
"""

# 頁首報價日期（P0：div.pricechangerow 內的 MM/DD/YY）。讀不到回 null，由 Ruby 判定失敗。
QUOTE_DATE_JS = """
(() => {
  const row = document.querySelector('.pricechangerow');
  if (!row) return null;
  const m = row.textContent.match(/\\b(\\d{2}\\/\\d{2}\\/\\d{2})\\b/);
  return m ? m[1] : null;
})()
"""

# overview 頁的「Historical Volatility 46.66%」。只認文字恰為 Historical Volatility 的標籤，
# 避開名詞說明裡的「30-Day Historical Volatility」。
HV_JS = """
(() => {
  const label = [...document.querySelectorAll('span, div, td, dt')].find(
    el => el.children.length === 0 && el.textContent.trim() === 'Historical Volatility');
  if (!label || !label.parentElement) return null;
  const m = label.parentElement.textContent.replace(/\\s+/g, ' ')
    .match(/Historical Volatility\\s*([0-9]+(?:\\.[0-9]+)?)\\s*%/);
  return m ? parseFloat(m[1]) : null;
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


def _signature(rows):
    """用列數與首尾日期判斷表格是否換了一批資料。"""
    if not rows:
        return None
    return (len(rows), rows[0].get("date"), rows[-1].get("date"))


async def _wait_for_grid(ws_url, target_id):
    for _ in range(int(GRID_MAX_WAIT_S / POLL_S)):
        rows = await cdp_eval(ws_url, GRID_JS, target_id=target_id)
        if isinstance(rows, list) and rows:
            return rows
        await asyncio.sleep(POLL_S)
    return None


async def _open_toggle(ws_url, target_id):
    await cdp_eval(ws_url,
                   "(() => { const a = document.querySelector('.bc-price-history-periods "
                   ".bc-dropdown-flexible-toggle'); if (a) a.click(); return !!a; })()",
                   target_id=target_id)
    await asyncio.sleep(0.5)


async def _select_period(ws_url, target_id, label):
    """
    點擊區間選項，等到 li.active 是 label 且表格資料穩定；回傳穩定後的 rows，失敗回 None。

    原本已是 label：表格不會換資料，穩定 MIN_SETTLE_S 秒就採信。
    原本是別的區間：**一定要等到表格換了一批資料**才採信——2026-11-06 P4 實跑，CSCO／ORCL／WULF
    的 2Y 回補只拿到 65 列：6 秒內表格還沒重載，舊的 3M 資料被當成穩定結果收下，而且記成 success。
    """
    already = ((await cdp_eval(ws_url, PERIOD_STATE_JS, target_id=target_id)) or {}).get("active") == label
    before = _signature(await cdp_eval(ws_url, GRID_JS, target_id=target_id))
    await _open_toggle(ws_url, target_id)
    if not await cdp_eval(ws_url, CLICK_PERIOD_JS % json.dumps(label), target_id=target_id):
        return None

    loop = asyncio.get_event_loop()
    start = loop.time()
    seen = []
    while loop.time() - start < PERIOD_WAIT_S:
        await asyncio.sleep(POLL_S)
        state = await cdp_eval(ws_url, PERIOD_STATE_JS, target_id=target_id) or {}
        rows = await cdp_eval(ws_url, GRID_JS, target_id=target_id)
        sig = _signature(rows if isinstance(rows, list) else None)
        seen.append(sig)
        stable = len(seen) >= STABLE_POLLS and sig is not None and len(set(seen[-STABLE_POLLS:])) == 1
        loaded = (loop.time() - start >= MIN_SETTLE_S) if already else (sig != before)
        if state.get("active") == label and stable and loaded:
            return rows
    return None


async def main(symbol, mode):
    symbol = symbol.upper()
    label = MODE_PERIODS[mode]
    source_url = f"https://www.barchart.com/stocks/quotes/{symbol}/{PAGE_TYPE}"

    target_id, ws_url = await prepare_page(symbol, PAGE_TYPE, settle_ms=2000)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    if await _wait_for_grid(ws_url, target_id) is None:
        if await cdp_eval(ws_url, SESSION_EXPIRED_JS, target_id=target_id):
            print(json.dumps({"status": "barchart_session_expired"}))
        else:
            print(json.dumps({"status": "error",
                              "error": "Options Overview History 表格遲遲沒有載入完成（非 Session 問題），請稍後重試"}))
        return

    state = await cdp_eval(ws_url, PERIOD_STATE_JS, target_id=target_id) or {}
    original = state.get("active")
    if label not in (state.get("options") or []):
        print(json.dumps({"status": "error",
                          "error": f"Select History 沒有 {label} 選項（實際：{state.get('options')}）"}))
        return

    rows = await _select_period(ws_url, target_id, label)
    quote_date_text = await cdp_eval(ws_url, QUOTE_DATE_JS, target_id=target_id)

    # 切回使用者原本的區間；失敗只記錄，不影響這次讀到的資料
    restored = None
    if original and original != label:
        restored_rows = await _select_period(ws_url, target_id, original)
        restored = original if restored_rows is not None else None
        if restored is None:
            sys.stderr.write(f"[barchart_iv_history] 無法切回原本的區間 {original}\n")

    if rows is None:
        print(json.dumps({"status": "error",
                          "error": f"切換到 {label} 後表格沒有在 {PERIOD_WAIT_S} 秒內穩定"}))
        return
    if mode == "latest":
        rows = rows[:1]

    hv_source_url = f"https://www.barchart.com/stocks/quotes/{symbol}/overview"
    await cdp_navigate(ws_url, hv_source_url, settle_ms=4000)
    await activate_target(target_id)
    hv_pct = None
    for _ in range(10):
        hv_pct = await cdp_eval(ws_url, HV_JS, target_id=target_id)
        if isinstance(hv_pct, (int, float)):
            break
        await asyncio.sleep(POLL_S)

    print(json.dumps({
        "status":          "success",
        "mode":            mode,
        "period_label":    label,
        "rows":            rows,
        "quote_date_text": quote_date_text if isinstance(quote_date_text, str) else None,
        "source_url":      source_url,
        "hv_pct":          hv_pct if isinstance(hv_pct, (int, float)) else None,
        "hv_source_url":   hv_source_url,
        "original_period": original,
        "restored_period": restored,
    }))


if __name__ == "__main__":
    sym  = sys.argv[1] if len(sys.argv) > 1 else "TSM"
    mode = sys.argv[2] if len(sys.argv) > 2 else "latest"
    if mode not in MODE_PERIODS:
        print(json.dumps({"status": "error", "error": f"mode 必須是 latest 或 backfill，收到 {mode!r}"}))
        sys.exit(0)
    try:
        asyncio.run(main(sym, mode))
    except Exception as e:
        import traceback
        print(json.dumps({
            "status": "error",
            "error": f"{type(e).__name__}: {e}",
            "traceback": traceback.format_exc(),
        }))
