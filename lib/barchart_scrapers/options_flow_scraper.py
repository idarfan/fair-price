"""
Barchart Options Flow scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 options_flow_scraper.py MU
"""
import asyncio
import json
import re
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval


TARGET_PATH = "options-flow"


def parse_dollar(s):
    if not s:
        return None
    try:
        return int(float(re.sub(r"[$,\s]", "", s)))
    except ValueError:
        return None


EXTRACT_JS = """
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


async def main(symbol):
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=8000)
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    stats = await cdp_eval(ws, EXTRACT_JS)

    if stats is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    if len(stats) < 3:
        print(json.dumps({"status": "dom_structure_changed",
                          "error": f"Only {len(stats)} stats found"}))
        return

    bearish_raw = parse_dollar(stats.get("Bearish Trade Sentiment"))
    data = {
        "bullish_sentiment": parse_dollar(stats.get("Bullish Trade Sentiment")),
        "bearish_sentiment": abs(bearish_raw) if bearish_raw is not None else None,
        "net_sentiment":     parse_dollar(stats.get("Net Trade Sentiment")),
        "bullish_delta":     parse_dollar(stats.get("Bullish Delta")),
        "bearish_delta":     parse_dollar(stats.get("Bearish Delta")),
        "delta_imbalance":   parse_dollar(stats.get("Delta Imbalance")),
        "status":            "success",
    }
    print(json.dumps(data))


if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
