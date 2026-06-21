"""
Barchart Options Flow scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 options_flow_scraper.py MU

Filters: Size >= 10, Premium >= $10 (as shown in filter UI)
Reads per-trade rows from bc-data-grid._data using .raw sub-objects.
Also triggers CSV download for backup.
"""
import asyncio
import json
import re
import sys
import os

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
            lastPrice:      typeof r.lastPrice === 'number' ? r.lastPrice : null,
            tradeCondition: tc,
            strikePrice:    r.strikePrice,
            expiration:     r.expiration
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


def parse_dollar(s):
    if not s:
        return None
    try:
        return int(float(re.sub(r"[$,\s]", "", s)))
    except ValueError:
        return None


async def apply_filters(ws):
    js = """
    (() => {
        const premInp = document.querySelector('input[name="premium1"]');
        if (premInp && (premInp.value === '' || premInp.value === '0')) {
            premInp.value = '10';
            premInp.dispatchEvent(new Event('input',  {bubbles: true}));
            premInp.dispatchEvent(new Event('change', {bubbles: true}));
        }
        const btn = document.querySelector('.bc-button.ok.light-blue');
        if (btn) btn.click();
        return !!btn;
    })()
    """
    return await cdp_eval(ws, js, timeout=5)


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
    """Paginate through all pages and collect every row."""
    all_rows = []
    page_rows = await cdp_eval(ws, EXTRACT_ROWS_JS, timeout=10) or []
    all_rows.extend(page_rows)

    page_num = 2
    MAX_PAGES = 20
    while page_num <= MAX_PAGES:
        next_pages = await cdp_eval(ws, PAGINATION_JS, timeout=5) or []
        if str(page_num) not in next_pages:
            break
        clicked = await click_page(ws, str(page_num))
        if not clicked:
            break
        await asyncio.sleep(GRID_SETTLE_S)
        page_rows = await cdp_eval(ws, EXTRACT_ROWS_JS, timeout=10) or []
        if not page_rows:
            break
        all_rows.extend(page_rows)
        page_num += 1

    return all_rows


def compute_flow_metrics(rows):
    call_rows = [r for r in rows if r.get("symbolType") == "Call"]
    put_rows  = [r for r in rows if r.get("symbolType") == "Put"]

    def prem_sum(lst, side=None):
        return sum(
            r["premium"] for r in lst
            if r.get("premium") is not None
            and (side is None or r.get("side") == side)
        )

    # Total premiums (all sides)
    call_prem = prem_sum(call_rows)
    put_prem  = prem_sum(put_rows)
    ratio = round(call_prem / put_prem, 3) if put_prem > 0 else None

    # Ask-side only (directional — aggressive buyers)
    ask_call = prem_sum(call_rows, side="ask")
    ask_put  = prem_sum(put_rows,  side="ask")
    ask_ratio = round(ask_call / ask_put, 3) if ask_put > 0 else None

    # Large orders (premium >= $500K), ask-side only for directional signal
    large_orders = [
        r for r in rows
        if (r.get("premium") or 0) >= 500_000
    ]
    large_call_count = sum(1 for r in large_orders if r.get("symbolType") == "Call")
    large_put_count  = sum(1 for r in large_orders if r.get("symbolType") == "Put")

    # Top 10 orders by premium (all rows, not limited to large_orders threshold)
    top_orders = sorted(
        [r for r in rows if r.get("premium")],
        key=lambda r: r["premium"],
        reverse=True
    )[:10]
    top_orders_clean = [
        {
            "symbolType":  r.get("symbolType"),
            "side":        r.get("side"),
            "premium":     r.get("premium"),
            "tradeSize":   r.get("tradeSize"),
            "dte":         r.get("dte"),
            "delta":       r.get("delta"),
            "strikePrice": r.get("strikePrice"),
            "expiration":  r.get("expiration"),
            "lastPrice":   r.get("lastPrice"),
        }
        for r in top_orders
    ]

    # High-delta call (ask-side, delta >= 0.70) — strong directional
    high_delta_call_count = sum(
        1 for r in call_rows
        if r.get("side") == "ask"
        and r.get("delta") is not None
        and abs(r["delta"]) >= 0.70
    )

    # Long DTE call (ask-side, DTE > 180) — institutional positioning
    long_dte_call_premium = prem_sum(
        [r for r in call_rows if r.get("side") == "ask" and (r.get("dte") or 0) > 180]
    )

    # Short DTE put (ask-side, DTE < 30) — short-term hedging
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


async def trigger_csv_download(ws):
    js = """
    (() => {
        const btn = document.querySelector('span.js-download-button.js-main-title, .js-download-button');
        if (btn) { btn.click(); return true; }
        return false;
    })()
    """
    return await cdp_eval(ws, js, timeout=5)


async def main(symbol):
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

    await apply_filters(ws)
    await asyncio.sleep(GRID_SETTLE_S)

    all_rows = await extract_all_rows(ws)
    flow_metrics = compute_flow_metrics(all_rows)

    await trigger_csv_download(ws)

    bearish_raw = parse_dollar(stats.get("Bearish Trade Sentiment"))
    data = {
        "bullish_sentiment": parse_dollar(stats.get("Bullish Trade Sentiment")),
        "bearish_sentiment": abs(bearish_raw) if bearish_raw is not None else None,
        "net_sentiment":     parse_dollar(stats.get("Net Trade Sentiment")),
        "bullish_delta":     parse_dollar(stats.get("Bullish Delta")),
        "bearish_delta":     parse_dollar(stats.get("Bearish Delta")),
        "delta_imbalance":   parse_dollar(stats.get("Delta Imbalance")),
        **flow_metrics,
        "status": "success",
    }
    print(json.dumps(data))


if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
