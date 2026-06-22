"""
Barchart Max Pain & Vol Skew scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout

Usage:
  python3 max_pain_scraper.py SYMBOL
  python3 max_pain_scraper.py SYMBOL YYYY-MM-DD-m   # specific expiration

Reads data directly from Highcharts.charts instances on the max-pain-chart page.
Charts layout (as of 2026-06-22 LIN verification):
  [0] Max Pain (calls pain + puts pain by strike, plotLines = last_price + max_pain_strike)
  [1] Open Interest by Strike (call OI positive, put OI negative)
  [2] Options Volatility Skew (call & put combined IV by strike)
  [3] Max Pain by Contract (max pain per expiry)
"""
import asyncio
import json
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH = "max-pain-chart"
PAGE_SETTLE_S = 8.0

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
      : []
  };
})()
"""


def build_output(symbol, expiration, raw):
    """Flatten Highcharts series into arrays keyed by strike."""
    if not raw or "error" in raw:
        return {"status": "charts_not_ready", "detail": raw}

    def to_dict(points):
        return {int(p["x"]): p["y"] for p in points}

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
        "status": "success",
    }


async def main(symbol, expiration=None):
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=int(PAGE_SETTLE_S * 1000))
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    # Navigate to specific expiration if requested
    if expiration:
        target_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}"
            f"/{TARGET_PATH}?expiration={expiration}"
        )
        current_url = await cdp_eval(ws, "window.location.href", timeout=10) or ""
        if expiration not in current_url:
            await cdp_navigate(ws, target_url, settle_ms=int(PAGE_SETTLE_S * 1000))

    # Check login
    logged_in = await cdp_eval(ws, "window.bcIsLogedIn", timeout=5)
    if not logged_in:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    # Wait for Highcharts to render (retry up to 3×)
    raw = None
    for attempt in range(3):
        raw = await cdp_eval(ws, EXTRACT_JS, timeout=15)
        if raw and "error" not in raw:
            break
        await asyncio.sleep(3)

    if not raw or "error" in raw:
        print(json.dumps({
            "status": "charts_not_ready",
            "detail": raw,
            "symbol": symbol,
        }))
        return

    result = build_output(symbol, expiration, raw)
    print(json.dumps(result))


if __name__ == "__main__":
    sym = sys.argv[1].upper() if len(sys.argv) > 1 else "LIN"
    exp = sys.argv[2] if len(sys.argv) > 2 else None
    asyncio.run(main(sym, exp))
