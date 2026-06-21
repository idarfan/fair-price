"""
Barchart Technical Analysis scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 technical_scraper.py MU
"""
import asyncio
import json
import re
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval


TARGET_PATH = "technical-analysis"


def clean_num(s):
    if not s:
        return None
    cleaned = re.sub(r"[+,%]", "", s.replace(",", "")).strip()
    try:
        return float(cleaned)
    except ValueError:
        return None


def clean_bigint(s):
    if not s:
        return None
    try:
        return int(float(re.sub(r"[+,]", "", s).strip()))
    except ValueError:
        return None


EXTRACT_JS = """
(() => {
    const main = document.querySelector('div.barchart-content-block.bc-technical-analysis');
    if (!main) return null;
    const wrappers = main.querySelectorAll('div.analysis-table-wrapper');
    return [...wrappers].map(w => {
        const rows = [...w.querySelectorAll('tbody tr')].map(tr =>
            [...tr.querySelectorAll('td')].map(td => td.textContent.trim())
        );
        return rows;
    });
})()
"""


async def main(symbol):
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=5000)
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    raw = await cdp_eval(ws, EXTRACT_JS)

    if raw is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    if len(raw) < 4:
        print(json.dumps({"status": "dom_structure_changed",
                          "error": f"Expected 4 tables, got {len(raw)}"}))
        return

    data = {}

    period_map = {
        "5-Day": "5d", "20-Day": "20d", "50-Day": "50d",
        "100-Day": "100d", "200-Day": "200d", "Year-to-Date": "ytd",
    }
    stoch_map = {
        "9-Day": "9d", "14-Day": "14d", "20-Day": "20d",
        "50-Day": "50d", "100-Day": "100d",
    }

    # Table 0 — Moving Average
    for row in raw[0]:
        p = period_map.get(row[0] if row else "")
        if not p or len(row) < 5:
            continue
        data[f"ma_{p}"]           = clean_num(row[1])
        data[f"ma_price_chg_{p}"] = clean_num(row[2])
        data[f"ma_pct_chg_{p}"]   = clean_num(row[3])
        data[f"ma_avg_vol_{p}"]   = clean_bigint(row[4])

    # Table 1 — Stochastic
    for row in raw[1]:
        p = stoch_map.get(row[0] if row else "")
        if not p or len(row) < 5:
            continue
        data[f"stoch_raw_{p}"] = clean_num(row[1])
        data[f"stoch_k_{p}"]   = clean_num(row[2])
        data[f"stoch_d_{p}"]   = clean_num(row[3])
        data[f"stoch_rs_{p}"]  = clean_num(row[4])

    # Table 2 — ATR
    for row in raw[2]:
        p = stoch_map.get(row[0] if row else "")
        if not p or len(row) < 5:
            continue
        data[f"atr_{p}"]     = clean_num(row[1])
        data[f"atr_pct_{p}"] = clean_num(row[2])
        data[f"adr_{p}"]     = clean_num(row[3])
        data[f"adr_pct_{p}"] = clean_num(row[4])

    # Table 3 — Directional Index
    for row in raw[3]:
        p = stoch_map.get(row[0] if row else "")
        if not p or len(row) < 5:
            continue
        data[f"adx_{p}"]      = clean_num(row[1])
        data[f"di_plus_{p}"]  = clean_num(row[2])
        data[f"di_minus_{p}"] = clean_num(row[3])
        data[f"hist_vol_{p}"] = clean_num(row[4])

    data["status"] = "success"
    print(json.dumps(data))


if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
