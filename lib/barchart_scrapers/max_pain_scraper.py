"""
Barchart Max Pain & Vol Skew scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout

Usage:
  python3 max_pain_scraper.py SYMBOL
  python3 max_pain_scraper.py SYMBOL 2026-08-21-m [show_all] [open_interest]

Filter defaults (when args omitted):
  expiration   -> first option in dropdown (nearest expiry)
  strikes      -> show_all
  volume_oi    -> open_interest

Reads data directly from Highcharts.charts instances on the max-pain-chart page.
Charts layout (as of 2026-06-22 LIN verification):
  [0] Max Pain (calls pain + puts pain by strike, plotLines = last_price + max_pain_strike)
  [1] Open Interest by Strike (call OI positive, put OI negative)
  [2] Options Volatility Skew (call & put combined IV by strike)
  [3] Max Pain by Contract (max pain per expiry)
"""
import asyncio
import json
import re
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH = "max-pain-chart"
PAGE_SETTLE_S = 8.0

MONEYNESS_MAP = {
    "le(nearestToLast,10)":  "5_strikes",
    "le(nearestToLast,20)":  "near_money",
    "le(nearestToLast,40)":  "20_strikes",
    "le(nearestToLast,100)": "50_strikes",
    "le(nearestToLast,200)": "show_all",
}

REVERSE_MONEYNESS_MAP = {v: k for k, v in MONEYNESS_MAP.items()}

# --- JS snippets ---

GET_FIRST_EXPIRY_JS = """
(() => {
  const sel = document.querySelector('select[name="expiration"]');
  if (!sel) return null;
  const firstOpt = Array.from(sel.options).find(o => o.value && o.value !== '');
  return firstOpt ? firstOpt.value : null;
})()
"""

def make_set_filters_js(expiry_value, moneyness_value, oi_value):
    return """
(() => {
  const expSel   = document.querySelector('select[name="expiration"]');
  const moneySel = document.querySelector('select[name="moneyness"]');
  const oiSel    = document.querySelector('select[name="openInterest"]');
  const showBtn  = document.querySelector('button.bc-button.ok.light-blue');

  if (!expSel || !moneySel || !oiSel || !showBtn) {
    return { error: 'elements_not_found' };
  }

  expSel.value   = """ + json.dumps(expiry_value) + """;
  moneySel.value = """ + json.dumps(moneyness_value) + """;
  oiSel.value    = """ + json.dumps(oi_value) + """;

  [expSel, moneySel, oiSel].forEach(el =>
    el.dispatchEvent(new Event('change', { bubbles: true }))
  );

  showBtn.click();

  return { expSet: expSel.value, moneySet: moneySel.value, oiSet: oiSel.value };
})()
"""

def make_wait_chart_js(title_fragment):
    return """
(() => {
  const charts = (window.Highcharts && Highcharts.charts || []).filter(Boolean);
  if (!charts.length) return false;
  return (charts[0].title?.textStr || '').includes(""" + json.dumps(title_fragment) + """);
})()
"""

EXTRACT_JS = """
(() => {
  const charts = (window.Highcharts && Highcharts.charts || []).filter(Boolean);
  if (charts.length < 3) return { error: 'charts_not_ready', count: charts.length };

  function seriesData(chart, seriesIndex) {
    const s = chart.series[seriesIndex];
    if (!s) return [];
    return s.data.map(p => ({ x: p.x, y: p.y }));
  }

  function plotLineValues(chart) {
    return (chart.xAxis?.[0]?.plotLinesAndBands || []).map(pl => ({
      value: pl.options?.value,
      label: pl.options?.label?.text || ''
    }));
  }

  const maxPainChart  = charts[0];
  const oiChart       = charts[1];
  const skewChart     = charts[2];
  const byExpiryChart = charts[3];

  const plotLines = plotLineValues(maxPainChart);
  let last_price     = null;
  let max_pain_strike = null;
  for (const pl of plotLines) {
    if ((pl.label || '').includes('Last Price'))
      last_price = pl.value;
    if ((pl.label || '').includes('Max Pain') && !pl.label.includes('Last'))
      max_pain_strike = pl.value;
  }

  const title = maxPainChart.title?.textStr || '';
  const dteMatch = title.match(/(\\d+)\\s*DTE/);

  // Read current filter state from Angular dropdowns (pure DOM read, no side effects)
  const expSel   = document.querySelector('select[name="expiration"]');
  const moneySel = document.querySelector('select[name="moneyness"]');
  const oiSel    = document.querySelector('select[name="openInterest"]');

  return {
    title,
    dte:             dteMatch ? parseInt(dteMatch[1]) : null,
    last_price,
    max_pain_strike,
    call_pain:       seriesData(maxPainChart, 0),
    put_pain:        seriesData(maxPainChart, 1),
    call_oi:         seriesData(oiChart,      0),
    put_oi:          seriesData(oiChart,      1),
    iv_combined:     seriesData(skewChart,    0),
    max_pain_by_expiry: byExpiryChart
      ? byExpiryChart.series[0]?.data.map(p => ({
          expiry: p.category,
          max_pain_strike: p.y
        }))
      : [],
    expiration_raw:  expSel?.value   || null,
    strikes_raw:     moneySel?.value || null,
    volume_oi_raw:   oiSel?.value    || null,
    expiration_options: Array.from(expSel?.options || [])
      .map(o => o.value)
      .filter(v => v && v !== ''),
  };
})()
"""


# --- Helpers ---

def parse_expiry_arg(arg):
    """Convert CLI arg "2026-06-26-w" to (display "2026-06-26 (w)", angular "string:2026-06-26 (w)")."""
    m = re.match(r'^(\d{4}-\d{2}-\d{2})-(w|m)$', arg)
    if m:
        date_part, period = m.group(1), m.group(2)
        display = f"{date_part} ({period})"
        return display, f"string:{display}"
    # Already in display form
    return arg, f"string:{arg}"


def expiry_display_to_title_fragment(display):
    """Convert "2026-06-26 (w)" -> "06/26/26" for chart title matching."""
    date_part = display.split(" ")[0]   # "2026-06-26"
    y, m, d = date_part.split("-")
    return f"{m}/{d}/{y[2:]}"           # "06/26/26"


def build_output(symbol, raw):
    """Flatten Highcharts series into arrays keyed by strike."""
    if not raw or "error" in raw:
        return {"status": "charts_not_ready", "detail": raw}

    def to_dict(points):
        return {int(p["x"]): p["y"] for p in points}

    # Normalize filter values from DOM readings
    exp_raw = raw.get("expiration_raw") or ""
    expiration = exp_raw.replace("string:", "").strip() if exp_raw else ""

    strikes_filter   = MONEYNESS_MAP.get(raw.get("strikes_raw", ""), "show_all")
    volume_oi_filter = raw.get("volume_oi_raw") or "open_interest"

    call_pain_map = to_dict(raw.get("call_pain", []))
    put_pain_map  = to_dict(raw.get("put_pain", []))
    call_oi_map   = to_dict(raw.get("call_oi", []))
    put_oi_map    = to_dict(raw.get("put_oi", []))
    iv_map        = to_dict(raw.get("iv_combined", []))

    strikes = sorted(set(
        list(call_pain_map.keys()) +
        list(put_pain_map.keys()) +
        list(iv_map.keys())
    ))

    return {
        "symbol":           symbol,
        "expiration":       expiration,
        "strikes_filter":   strikes_filter,
        "volume_oi_filter": volume_oi_filter,
        "dte":              raw.get("dte"),
        "last_price":       raw.get("last_price"),
        "max_pain_strike":  raw.get("max_pain_strike"),
        "strikes":          strikes,
        "call_pain":        [call_pain_map.get(s) for s in strikes],
        "put_pain":         [put_pain_map.get(s) for s in strikes],
        "call_oi":          [call_oi_map.get(s) for s in strikes],
        "put_oi":           [abs(put_oi_map.get(s, 0)) for s in strikes],
        "iv_combined":      [iv_map.get(s) for s in strikes],
        "max_pain_by_expiry": raw.get("max_pain_by_expiry", []),
        "available_expirations": [v.replace("string:", "").strip() for v in raw.get("expiration_options", [])],
        "status": "success",
    }


async def main(symbol, expiry_arg=None, strikes_arg=None, oi_arg=None):
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=int(PAGE_SETTLE_S * 1000))
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    # Check login
    logged_in = await cdp_eval(ws, "window.bcIsLogedIn", timeout=5)
    if not logged_in:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    # --- Determine target filter values ---
    if expiry_arg:
        expiry_display, expiry_angular = parse_expiry_arg(expiry_arg)
    else:
        # Read first available option from dropdown
        first_val = await cdp_eval(ws, GET_FIRST_EXPIRY_JS, timeout=10)
        if not first_val:
            print(json.dumps({"status": "error", "error": "Cannot read expiration dropdown"}))
            return
        expiry_angular = first_val                             # "string:2026-06-26 (w)"
        expiry_display = first_val.replace("string:", "").strip()  # "2026-06-26 (w)"

    strikes_angular = REVERSE_MONEYNESS_MAP.get(strikes_arg or "show_all", "le(nearestToLast,200)")
    oi_angular      = oi_arg or "open_interest"

    # --- Set filters + click SHOW CHART (always, regardless of current state) ---
    set_result = await cdp_eval(
        ws, make_set_filters_js(expiry_angular, strikes_angular, oi_angular), timeout=10
    )
    if isinstance(set_result, dict) and "error" in set_result:
        print(json.dumps({"status": "error", "error": f"Filter setup failed: {set_result}"}))
        return

    # --- Wait for Highcharts to re-render with expected expiry in title ---
    title_fragment = expiry_display_to_title_fragment(expiry_display)
    rendered = False
    for _ in range(20):   # poll up to 10 seconds (0.5s intervals)
        check = await cdp_eval(ws, make_wait_chart_js(title_fragment), timeout=5)
        if check:
            rendered = True
            break
        await asyncio.sleep(0.5)

    if not rendered:
        print(json.dumps({
            "status": "charts_not_ready",
            "detail": f"Timed out waiting for title fragment: {title_fragment}",
            "symbol": symbol,
        }))
        return

    # --- Extract data ---
    raw = await cdp_eval(ws, EXTRACT_JS, timeout=15)
    if not raw or "error" in raw:
        print(json.dumps({"status": "charts_not_ready", "detail": raw, "symbol": symbol}))
        return

    result = build_output(symbol, raw)
    print(json.dumps(result))


if __name__ == "__main__":
    sym      = sys.argv[1].upper() if len(sys.argv) > 1 else "LIN"
    exp_arg  = sys.argv[2] if len(sys.argv) > 2 else None
    stk_arg  = sys.argv[3] if len(sys.argv) > 3 else None
    oi_arg   = sys.argv[4] if len(sys.argv) > 4 else None
    asyncio.run(main(sym, exp_arg, stk_arg, oi_arg))
