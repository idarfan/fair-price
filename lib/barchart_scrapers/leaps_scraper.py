"""
Barchart LEAPS option chain scraper (CDP direct WebSocket — no Playwright).

Fetches Options Prices + Volatility & Greeks for ALL available expirations,
merges by (strikePrice, expirationDate), and returns complete per-contract rows.

Login check: once at entry before the expiration loop.
Session expiry mid-loop: aborts cleanly, returns partial results with
  expired_at_expiration so the caller knows the table is incomplete.

Output JSON (stdout):
  success → {"status": "success", "rows": [...], "underlying_price": N}
  partial → {"status": "partial", "rows": [...], "expired_at_expiration": "YYYY-MM-DD"}
  expired → {"status": "barchart_session_expired"}
  error   → {"status": "error", "error": "..."}

Usage: python3 leaps_scraper.py SYMBOL
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH = "options"
OPTIONS_SETTLE_MS = 5000
VG_SETTLE_MS = 4000

# Read all available expiration dates from the Angular select element.
EXPIRATIONS_JS = """
(() => {
  const sel = [...document.querySelectorAll('select')].find(
    s => s.className.includes('ng-') && s.options.length > 3 &&
         [...s.options].some(o => /\\d{4}-\\d{2}-\\d{2}/.test(o.value))
  );
  if (!sel) return null;
  return [...sel.options].map(o => ({ value: o.value, text: o.text.trim() }));
})()
"""

# Try Angular rootScope first, fall back to moneyness-derived median.
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

  // Fallback: median of (strike / (1 - moneyness)) across ITM rows
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  const prices = grid._data
    .map(r => r.raw || r)
    .filter(r => typeof r.moneyness === 'number' &&
                 r.moneyness > 0.05 && r.moneyness < 0.95 &&
                 r.strikePrice > 0)
    .map(r => r.strikePrice / (1 - r.moneyness));
  if (!prices.length) return null;
  prices.sort((a, b) => a - b);
  const median = prices[Math.floor(prices.length / 2)];
  return Math.round(median * 100) / 100;
})()
"""

# Extract Call rows from Options Prices bc-data-grid.
OPTIONS_GRID_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data
    .map(r => r.raw || r)
    .filter(r => r.optionType === 'Call' || r.symbolType === 'Call')
    .map(r => ({
      strike:    r.strikePrice,
      dte:       typeof r.daysToExpiration === 'number' ? r.daysToExpiration : null,
      bid:       typeof r.bidPrice   === 'number' ? r.bidPrice   : null,
      ask:       typeof r.askPrice   === 'number' ? r.askPrice   : null,
      mid:       typeof r.midpoint   === 'number' ? r.midpoint   : null,
      last:      typeof r.lastPrice  === 'number' ? r.lastPrice  : null,
      volume:    typeof r.volume     === 'number' ? r.volume     : null,
      oi:        typeof r.openInterest === 'number' ? r.openInterest : null,
      delta:     typeof r.delta      === 'number' ? r.delta      : null,
      iv:        typeof r.volatility === 'number' ? r.volatility : null,
      moneyness: typeof r.moneyness  === 'number' ? r.moneyness  : null,
    }));
})()
"""

# Extract itmProbability, volumeOpenInterestRatio, and vega from V&G bc-data-grid.
VG_GRID_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data
    .map(r => r.raw || r)
    .filter(r => r.optionType === 'Call' || r.symbolType === 'Call')
    .map(r => ({
      strike:   r.strikePrice,
      itm_prob: typeof r.itmProbability          === 'number' ? r.itmProbability          : null,
      vol_oi:   typeof r.volumeOpenInterestRatio === 'number' ? r.volumeOpenInterestRatio : null,
      vega:     typeof r.vega                    === 'number' ? r.vega                    : null,
    }));
})()
"""


def _merge_vg(options_rows, vg_rows):
    """Merge V&G extra fields into options rows keyed by strikePrice."""
    vg_by_strike = {r["strike"]: r for r in (vg_rows or [])}
    return [
        {**row,
         "itm_probability": vg_by_strike.get(row["strike"], {}).get("itm_prob"),
         "vol_oi_ratio":    vg_by_strike.get(row["strike"], {}).get("vol_oi"),
         "vega":            vg_by_strike.get(row["strike"], {}).get("vega")}
        for row in options_rows
    ]


def _finalize_rows(rows, exp_date, underlying_price):
    """Normalize field names and attach expiration/underlying to each row."""
    return [
        {
            "expiration_date":  exp_date,
            "dte":              r.get("dte"),
            "strike":           r.get("strike"),
            "option_type":      "Call",
            "bid":              r.get("bid"),
            "ask":              r.get("ask"),
            "last_price":       r.get("last"),
            "underlying_price": underlying_price,
            "volume":           r.get("volume"),
            "open_interest":    r.get("oi"),
            "delta":            r.get("delta"),
            "iv":               r.get("iv"),
            "itm_probability":  r.get("itm_probability"),
            "vol_oi_ratio":     r.get("vol_oi_ratio"),
            "vega":             r.get("vega"),
        }
        for r in rows
    ]


async def main(symbol):
    symbol = symbol.upper()

    # Navigate to options page — serves as both initial load and login check.
    target_id, ws_url = await prepare_page(
        symbol, TARGET_PATH, settle_ms=OPTIONS_SETTLE_MS
    )
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    # Login check: null grid data means session has expired.
    initial_data = await cdp_eval(ws_url, OPTIONS_GRID_JS)
    if initial_data is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    expirations = await cdp_eval(ws_url, EXPIRATIONS_JS)
    if not expirations:
        print(json.dumps({"status": "error", "error": "Could not read expiration list"}))
        return

    all_rows = []
    underlying_price = None

    for exp in expirations:
        exp_value = exp["value"]   # e.g. "2027-01-15-m"
        exp_date  = exp_value[:10] # "2027-01-15"

        # -- Options Prices (Call side, all strikes) --
        opts_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/options"
            f"?expiration={exp_value}&moneyness=allRows&view=sbs"
        )
        await cdp_navigate(ws_url, opts_url, settle_ms=OPTIONS_SETTLE_MS)
        await activate_target(target_id)

        opts_rows = await cdp_eval(ws_url, OPTIONS_GRID_JS)
        if opts_rows is None:
            print(json.dumps({
                "status":                "partial",
                "rows":                  all_rows,
                "expired_at_expiration": exp_date,
            }))
            return

        # Grab underlying_price once from the first expiration that has data.
        if underlying_price is None and opts_rows:
            underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)

        # -- Volatility & Greeks (Call side, all strikes) --
        vg_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/volatility-greeks"
            f"?expiration={exp_value}&moneyness=allRows"
        )
        await cdp_navigate(ws_url, vg_url, settle_ms=VG_SETTLE_MS)
        await activate_target(target_id)

        vg_rows = await cdp_eval(ws_url, VG_GRID_JS)
        if vg_rows is None:
            # Session expired after opts_rows already fetched — include this
            # expiration with empty V&G fields, then abort cleanly.
            merged = _merge_vg(opts_rows, [])
            all_rows.extend(_finalize_rows(merged, exp_date, underlying_price))
            print(json.dumps({
                "status":                "partial",
                "rows":                  all_rows,
                "expired_at_expiration": exp_date,
            }))
            return

        merged = _merge_vg(opts_rows, vg_rows)
        all_rows.extend(_finalize_rows(merged, exp_date, underlying_price))

        await asyncio.sleep(0.8)  # brief pause between expiration pairs

    print(json.dumps({
        "status":           "success",
        "rows":             all_rows,
        "underlying_price": underlying_price,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "NOK"
    asyncio.run(main(sym))
