"""
Barchart Options Flow scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 options_flow_scraper.py MU

Filters: Size >= 10, Premium >= $10 (as shown in filter UI)
Reads per-trade rows from bc-data-grid._data using .raw sub-objects.
Downloads CSV to csv_files/options_flow/{SYMBOL}_{YYYY-MM-DD}.csv,
parses it, and returns both summary metrics + raw trades array.
"""
import asyncio
import csv
import json
import os
import re
import sys
import subprocess
import time
from datetime import date
from pathlib import Path

import websockets

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, get_browser_ws

TARGET_PATH = "options-flow"
GRID_SETTLE_S = 2.5

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
CSV_DIR = PROJECT_ROOT / "csv_files" / "options_flow"

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


# ---------------------------------------------------------------------------
# CSV parse helpers
# ---------------------------------------------------------------------------

def _parse_num(s):
    if not s:
        return None
    try:
        return float(re.sub(r"[$,%\s]", "", str(s)))
    except (ValueError, TypeError):
        return None


def _parse_int(s):
    v = _parse_num(s)
    return int(v) if v is not None else None


def _parse_dollar(s):
    if not s:
        return None
    try:
        return int(float(re.sub(r"[$,\s]", "", str(s))))
    except (ValueError, TypeError):
        return None


def _parse_pct(s):
    """Parse "25.4%" -> 0.254 or "0.254" -> 0.254."""
    if not s:
        return None
    s = str(s).strip()
    try:
        val = float(re.sub(r"[%\s]", "", s))
        return round(val / 100, 6) if val > 1 else val
    except (ValueError, TypeError):
        return None


def parse_csv_trades(csv_path):
    trades = []
    try:
        with open(csv_path, newline="", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            for row in reader:
                trades.append({
                    "option_type":     (row.get("Type") or "").strip() or None,
                    "strike":          _parse_num(row.get("Strike")),
                    "expires_at":      (row.get("Expires") or "").strip() or None,
                    "dte":             _parse_int(row.get("DTE")),
                    "trade_price":     _parse_num(row.get("Trade")),
                    "size":            _parse_int(row.get("Size")),
                    "side":            (row.get("Side") or "").strip().lower() or None,
                    "premium":         _parse_dollar(row.get("Premium")),
                    "volume":          _parse_int(row.get("Volume")),
                    "open_interest":   _parse_int(row.get("Open Int")),
                    "iv":              _parse_pct(row.get("IV")),
                    "delta":           _parse_num(row.get("Delta")),
                    "trade_condition": (row.get("Code") or "").strip() or None,
                    "open_close":      (row.get("*") or "").strip() or None,
                    "trade_time":      (row.get("Time") or "").strip() or None,
                })
    except Exception as exc:
        return {"error": str(exc)}
    return trades


# ---------------------------------------------------------------------------
# CDP download helpers
# ---------------------------------------------------------------------------

def to_windows_path(linux_path: Path) -> str:
    """Convert WSL2 Linux path to Windows UNC path for Chrome CDP.

    Chrome runs on Windows, so it cannot resolve Linux paths like
    /home/... — needs \\\\wsl.localhost\\Ubuntu\\home\\...
    Falls back to Linux path string if wslpath is unavailable.
    """
    try:
        result = subprocess.run(
            ["wslpath", "-w", str(linux_path)],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"[warn] wslpath failed: {e}", file=sys.stderr)
        return str(linux_path)


async def set_download_path(download_dir):
    """Use Browser.setDownloadBehavior (browser-level, persists across CDP sessions)."""
    download_dir.mkdir(parents=True, exist_ok=True)
    browser_ws = get_browser_ws()
    async with websockets.connect(browser_ws, open_timeout=10) as ws:
        await ws.send(json.dumps({
            "id": 99,
            "method": "Browser.setDownloadBehavior",
            "params": {
                "behavior": "allow",
                "downloadPath": to_windows_path(download_dir),  # Windows UNC path for Chrome
            },
        }))
        try:
            resp = await asyncio.wait_for(ws.recv(), timeout=5)
            import sys; print(f"[debug] Browser.setDownloadBehavior: {resp}", file=sys.stderr)
        except asyncio.TimeoutError:
            pass


async def wait_for_csv(download_dir, timeout=30):
    before = set(download_dir.glob("*.csv"))
    deadline = time.time() + timeout
    while time.time() < deadline:
        await asyncio.sleep(0.8)
        after = set(download_dir.glob("*.csv"))
        new_files = after - before
        if new_files:
                return new_files.pop()
    print(f"[debug] wait_for_csv TIMEOUT, after={set(download_dir.glob("*.csv"))}", file=sys.stderr)
    return None


def rename_to_convention(csv_path, symbol, today_str):
    target = csv_path.parent / f"{symbol}_{today_str}.csv"
    if target.exists():
        target.unlink()
    csv_path.rename(target)
    return target


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


async def trigger_csv_download(ws):
    js = """
    (() => {
        // Real download button: toolbar-level [data-bc-download-button]
        const btn = document.querySelector('[data-bc-download-button]');
        if (btn) { btn.click(); return true; }
        return false;
    })()
    """
    return await cdp_eval(ws, js, timeout=5)


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

    await apply_filters(ws)
    await asyncio.sleep(GRID_SETTLE_S)

    all_rows = await extract_all_rows(ws)
    flow_metrics = compute_flow_metrics(all_rows)

    # Keep browser WS open for entire download sequence —
    # Browser.setDownloadBehavior resets when the CDP session closes
    trades = []
    csv_error = None
    CSV_DIR.mkdir(parents=True, exist_ok=True)
    async with websockets.connect(get_browser_ws(), open_timeout=10) as bws:
        await bws.send(json.dumps({
            "id": 99,
            "method": "Browser.setDownloadBehavior",
            "params": {
                "behavior": "allow",
                "downloadPath": to_windows_path(CSV_DIR),
            },
        }))
        try:
            resp = await asyncio.wait_for(bws.recv(), timeout=5)
            print(f"[debug] Browser.setDownloadBehavior: {resp}", file=sys.stderr)
        except asyncio.TimeoutError:
            pass

        clicked = await trigger_csv_download(ws)
    
        if clicked:
            csv_path = await wait_for_csv(CSV_DIR, timeout=30)
            if csv_path:
                final_path = rename_to_convention(csv_path, symbol, today_str)
                result = parse_csv_trades(final_path)
                if isinstance(result, list):
                    trades = result
                else:
                    csv_error = result.get("error")
            else:
                csv_error = "csv_download_timeout"
        else:
            csv_error = "download_button_not_found"

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
        "csv_error":         csv_error,
        "status":            "success",
    }
    print(json.dumps(data))


if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
