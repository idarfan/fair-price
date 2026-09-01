"""
Barchart Options Flow scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 options_flow_scraper.py MU

Filters: Size >= 10, Premium >= $10 (as shown in filter UI)
Reads per-trade rows from bc-data-grid._data using .raw sub-objects —
the same rows feed both the summary metrics and the per-trade array.

2026-09-01: 拿掉了「點下載鈕存 CSV 再解析」那條路。實測 `_data[*].raw` 是 CSV
欄位的超集（volume / openInterest / volatility / label / tradeTime 都在），
BE 當日兩邊都是 200 筆；而 CSV 末行是 Barchart 的頁尾字串，DictReader 沒過濾，
每個快照都會多寫一列全 null 的假交易進 DB（清理前累積 67 列）。
"""
import asyncio
import json
import os
import re
import sys
from datetime import date, datetime
from zoneinfo import ZoneInfo


sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval

TARGET_PATH = "options-flow"
GRID_SETTLE_S = 2.5

# Exchange condition codes that correspond to block-style (auction-based) trades.
BLOCK_CODES = {"ISOI", "MLAT"}

SUMMARY_JS = """
(() => {
    const container = document.querySelector('div.bc-futures-options-quotes-totals');
    if (!container) return null;
    const rows = container.querySelectorAll('div.bc-futures-options-quotes-totals__data-row');
    const stats = {};
    for (const row of rows) {
        const lines = (row.innerText || '').trim().split('\\n').map(s => s.trim()).filter(Boolean);
        if (lines.length >= 2) stats[lines[0]] = lines[1];
    }
    return stats;
})()
"""

EXTRACT_ROWS_JS = """
(() => {
    const grid = document.querySelector('bc-data-grid');
    if (!grid || !grid._data) return [];
    return grid._data.map(row => {
        const r = row.raw || row;
        const tc = (r.tradeCondition || '').split(' - ')[0].trim();
        return {
            symbolType:     r.symbolType,
            side:           r.side,
            premium:        typeof r.premium === 'number'   ? r.premium   : null,
            tradeSize:      typeof r.tradeSize === 'number' ? r.tradeSize : null,
            dte:            typeof r.dte === 'number'       ? r.dte       : null,
            delta:          typeof r.delta === 'number'     ? r.delta     : null,
            tradePrice:     typeof r.tradePrice === 'number' ? r.tradePrice
                            : typeof r.lastPrice === 'number' ? r.lastPrice
                            : null,
            tradeCondition: tc,
            strikePrice:    r.strikePrice,
            expiration:     r.expiration,
            volume:         typeof r.volume === 'number'       ? r.volume       : null,
            openInterest:   typeof r.openInterest === 'number' ? r.openInterest : null,
            volatility:     typeof r.volatility === 'number'   ? r.volatility   : null,
            label:          r.label,
            tradeTime:      typeof r.tradeTime === 'number'    ? r.tradeTime    : null
        };
    });
})()
"""

PAGINATION_JS = """
(() => {
    const nextLinks = [...document.querySelectorAll(
        '.bc-table-pagination a.next:not(.ng-hide)'
    )];
    return nextLinks.map(a => a.textContent.trim()).filter(t => /^\\d+$/.test(t));
})()
"""


# ---------------------------------------------------------------------------
# Grid rows -> trades
# ---------------------------------------------------------------------------

# Ruby 端（BarchartScraperService#classify_trade）依這組 key 取值，所以欄位名稱
# 沿用原本 CSV 解析產出的那 15 個，不要改名——改名等於同時要動分類器與面板。
def _et_time(epoch):
    """Unix epoch -> "HH:MM:SS ET"，對齊 DB 既有的 trade_time 字串格式。"""
    if not isinstance(epoch, (int, float)) or isinstance(epoch, bool):
        return None
    try:
        return datetime.fromtimestamp(epoch, ZoneInfo("America/New_York")).strftime("%H:%M:%S ET")
    except (ValueError, OSError, OverflowError):
        return None


# grid 的 label 是長格式（"(S) - Sell To Open"），CSV 給的是短格式（"SellToOpen"），
# 而 OptionsFlowClassifierService#derive_direction 是拿短格式做 pattern match
# （"BuyToOpen" / "SellToOpen"，"ToOpen" 屬 AMBIGUOUS_OPEN_CLOSE）。
# 不正規化的話方向判斷會全部落到 INDETERMINATE，而且不會有任何錯誤訊息。
def _open_close(label):
    if not label:
        return "N/A"
    text = str(label).split(" - ")[-1]          # "(S) - Sell To Open" -> "Sell To Open"
    return text.replace(" ", "") or "N/A"       # -> "SellToOpen"


def grid_rows_to_trades(rows):
    """
    把 extract_all_rows() 的 grid 列轉成逐筆交易。

    只有三個欄位需要轉換，其餘同名直取：
      volatility  33.28 代表 33.28% -> 一律 ÷100（舊 CSV 的 _parse_pct 是「>1 才除」，
                  對 0.8% 這種小值會算錯，改成無條件除，順帶修掉那個邊界 bug）
      tradeTime   Unix epoch -> "HH:MM:SS ET"
      label       "(S) - Sell To Open" -> "SellToOpen"、null -> "N/A"
                  （見 _open_close：classifier 用短格式做 pattern match）
    """
    trades = []
    for r in rows:
        vol = r.get("volatility")
        trades.append({
            "option_type":     r.get("symbolType"),
            "strike":          r.get("strikePrice"),
            "expires_at":      r.get("expiration"),
            "dte":             r.get("dte"),
            "trade_price":     r.get("tradePrice"),
            "size":            r.get("tradeSize"),
            "side":            (r.get("side") or "").strip().lower() or None,
            "premium":         r.get("premium"),
            "volume":          r.get("volume"),
            "open_interest":   r.get("openInterest"),
            "iv":              round(vol / 100, 6) if isinstance(vol, (int, float)) else None,
            "delta":           r.get("delta"),
            "trade_condition": (r.get("tradeCondition") or "").strip() or None,
            "open_close":      _open_close(r.get("label")),
            "trade_time":      _et_time(r.get("tradeTime")),
        })
    return trades


# ---------------------------------------------------------------------------
# Grid / flow helpers
# ---------------------------------------------------------------------------

def parse_dollar(s):
    if not s:
        return None
    try:
        return int(float(re.sub(r"[$,\s]", "", s)))
    except ValueError:
        return None


async def expand_filter_panel(ws):
    """Click 'Filter to Optimize Results' to expand the panel if currently collapsed."""
    js = """
    (() => {
        const btn = document.querySelector('a.filters-control.show-filters');
        // ng-hide means already expanded; no ng-hide means collapsed → need to click
        if (btn && !btn.classList.contains('ng-hide')) {
            btn.click();
            return 'expanded';
        }
        return 'already_open';
    })()
    """
    result = await cdp_eval(ws, js, timeout=5)
    if result == 'expanded':
        await asyncio.sleep(1.5)  # wait for Angular to render filter rows
    return result


async def apply_filters(ws):
    """
    Explicitly set ALL filter groups to ALL before clicking Apply.
    Never rely on page default/residual state.
    """
    js = """
    (() => {
        function ensureChecked(id) {
            const el = document.getElementById(id);
            if (el && !el.checked) {
                el.click();
            }
        }

        // Trade Sentiment
        ['ALL','Bullish','Bearish','Neither'].forEach(v =>
            ensureChecked('bc-sentiment-param-' + v));

        // Side
        ['ALL','Bid','Ask','Mid'].forEach(v =>
            ensureChecked('bc-side-param-' + v));

        // Flags: click ALL only (Angular binding toggles sub-items)
        ensureChecked('bc-flags-param-ALL');

        // To Open / Label
        ['ALL','BuyToOpen','ToOpen','SellToOpen'].forEach(v =>
            ensureChecked('bc-label-param-' + v));

        // Code — ALL master checkbox (sub-codes follow Angular binding)
        ensureChecked('bc-code-param-ALL');

        // Premium: clear upper bound; set lower to 10 (Barchart default threshold)
        const prem1 = document.querySelector('input[name="premium1"]');
        if (prem1) {
            prem1.value = '10';
            prem1.dispatchEvent(new Event('input',  {bubbles: true}));
            prem1.dispatchEvent(new Event('change', {bubbles: true}));
        }
        const prem2 = document.querySelector('input[name="premium2"]');
        if (prem2 && prem2.value !== '') {
            prem2.value = '';
            prem2.dispatchEvent(new Event('input',  {bubbles: true}));
            prem2.dispatchEvent(new Event('change', {bubbles: true}));
        }

        // Apply
        const btn = document.querySelector('button.bc-button.ok');
        if (btn) { btn.click(); return true; }
        return false;
    })()
    """
    return await cdp_eval(ws, js, timeout=15)


async def click_page(ws, page_num):
    js = f"""
    (() => {{
        const links = [...document.querySelectorAll(
            '.bc-table-pagination a.next:not(.ng-hide)'
        )];
        const target = links.find(a => a.textContent.trim() === '{page_num}');
        if (target) {{ target.click(); return true; }}
        return false;
    }})()
    """
    return await cdp_eval(ws, js, timeout=5)


async def extract_all_rows(ws):
    all_rows = []
    page_rows = await cdp_eval(ws, EXTRACT_ROWS_JS, timeout=10) or []
    all_rows.extend(page_rows)

    visited = set()
    while True:
        next_pages = await cdp_eval(ws, PAGINATION_JS, timeout=5) or []
        next_pages = [p for p in next_pages if p not in visited]
        if not next_pages:
            break
        next_p = next_pages[0]
        visited.add(next_p)
        await click_page(ws, next_p)
        await asyncio.sleep(GRID_SETTLE_S)
        page_rows = await cdp_eval(ws, EXTRACT_ROWS_JS, timeout=10) or []
        all_rows.extend(page_rows)

    return all_rows


def prem_sum(rows):
    return sum(r.get("premium") or 0 for r in rows)


def compute_flow_metrics(rows):
    call_rows = [r for r in rows if r.get("symbolType") == "Call"]
    put_rows  = [r for r in rows if r.get("symbolType") == "Put"]
    call_prem = prem_sum(call_rows)
    put_prem  = prem_sum(put_rows)
    ratio     = round(call_prem / put_prem, 4) if put_prem else None
    ask_call  = prem_sum([r for r in call_rows if r.get("side") == "ask"])
    ask_put   = prem_sum([r for r in put_rows  if r.get("side") == "ask"])
    ask_ratio = round(ask_call / ask_put, 4) if ask_put else None

    large_orders     = [r for r in rows if (r.get("premium") or 0) >= 500_000]
    large_call_count = sum(1 for r in large_orders if r.get("symbolType") == "Call")
    large_put_count  = sum(1 for r in large_orders if r.get("symbolType") == "Put")

    top_orders = sorted(
        [r for r in rows if r.get("premium")],
        key=lambda r: r["premium"], reverse=True
    )[:40]
    top_orders_clean = [
        {k: r.get(v) for k, v in {
            "symbolType": "symbolType", "side": "side", "premium": "premium",
            "tradeSize": "tradeSize", "dte": "dte", "delta": "delta",
            "strikePrice": "strikePrice", "expiration": "expiration",
            "tradePrice": "tradePrice",
        }.items()}
        for r in top_orders
    ]

    high_delta_call_count = sum(
        1 for r in call_rows
        if r.get("side") == "ask"
        and r.get("delta") is not None
        and abs(r["delta"]) >= 0.70
    )
    long_dte_call_premium = prem_sum(
        [r for r in call_rows if r.get("side") == "ask" and (r.get("dte") or 0) > 180]
    )
    short_dte_put_premium = prem_sum(
        [r for r in put_rows if r.get("side") == "ask" and (r.get("dte") or 999) < 30]
    )

    return {
        "call_premium_total":    call_prem,
        "put_premium_total":     put_prem,
        "call_put_ratio":        ratio,
        "ask_call_premium":      ask_call,
        "ask_put_premium":       ask_put,
        "ask_call_put_ratio":    ask_ratio,
        "large_call_count":      large_call_count,
        "large_put_count":       large_put_count,
        "high_delta_call_count": high_delta_call_count,
        "long_dte_call_premium": long_dte_call_premium,
        "short_dte_put_premium": short_dte_put_premium,
        "top_large_orders":      top_orders_clean,
        "sweep_block_count":     sum(1 for r in rows if r.get("tradeCondition") in BLOCK_CODES),
        "total_trades_loaded":   len(rows),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main(symbol):
    today_str = date.today().isoformat()
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=8000)
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    stats = await cdp_eval(ws, SUMMARY_JS)
    if stats is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    if len(stats) < 3:
        print(json.dumps({
            "status": "dom_structure_changed",
            "error": f"Only {len(stats)} stats found",
        }))
        return

    await expand_filter_panel(ws)
    await apply_filters(ws)
    await asyncio.sleep(GRID_SETTLE_S)

    all_rows = await extract_all_rows(ws)
    flow_metrics = compute_flow_metrics(all_rows)

    # 逐筆交易與彙總指標同源：都來自上面 extract_all_rows() 抓到的 grid 列，
    # 不再另外點下載鈕存 CSV（那條路的欄位是這裡的子集，還會多塞一列頁尾垃圾）。
    trades = grid_rows_to_trades(all_rows)

    bearish_raw = parse_dollar(stats.get("Bearish Trade Sentiment"))
    data = {
        "bullish_sentiment": parse_dollar(stats.get("Bullish Trade Sentiment")),
        "bearish_sentiment": abs(bearish_raw) if bearish_raw is not None else None,
        "net_sentiment":     parse_dollar(stats.get("Net Trade Sentiment")),
        "bullish_delta":     parse_dollar(stats.get("Bullish Delta")),
        "bearish_delta":     parse_dollar(stats.get("Bearish Delta")),
        "delta_imbalance":   parse_dollar(stats.get("Delta Imbalance")),
        **flow_metrics,
        "trades":            trades,
        "status":            "success",
    }
    print(json.dumps(data))


if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
