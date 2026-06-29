"""
Barchart LEAPS option chain scraper — Stacked view strategy (Phase G).

Two-stage approach:
  Stage 1  Load Near the Money view:
           • read all visible strikes + Deltas
           • determine candidate strikes (Delta>=0.80, or user-supplied center)
           • add ±1 buffer strike on each side
           • read expirations select (kept for V&G per-exp fallback)
           • read underlying price
  Stage 2  Per candidate strike:
           * OPTIONS  ?view=stacked&strike=X  -> all expirations at once
           * V&G      ?expiration={first_exp}&strike=X  -> all expirations for this strike
             empty → not supported, fall back to per-expiration V&G for the
             union of expiration dates found in Stage 2 Options data)

User-specified strike (optional sys.argv[2]):
  • Replaces Stage 1 auto-detection; used as the center point.
  • Buffer (±1 from near-money list) and Stage 2 / final-filter logic are UNCHANGED.
  • This is NOT "query only this one strike" — it is "start Stage 1 here".

Usage:  python3 leaps_scraper.py SYMBOL [USER_STRIKE]

Output JSON (stdout):
  success       → {"status":"success","rows":[...],"underlying_price":N}
  partial       → {"status":"partial","rows":[...],"expired_at_strike":N,"expired_layer":"..."}
              OR {"status":"partial","rows":[...],"expired_at_expiration":"YYYY-MM-DD","expired_layer":"volatility_greeks"}
  no_candidates → {"status":"no_candidates"}   # auto mode: no Delta>=0.80 in near-money
  expired       → {"status":"barchart_session_expired"}
  error         → {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH    = "options"
OPTIONS_SETTLE = 5000
VG_SETTLE      = 4000

# ── Stage 1: Near the Money view — all Call strikes + Deltas ─────────────────
NEAR_MONEY_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  const rows = grid._data
    .map(r => r.raw || r)
    .filter(r => (r.optionType === 'Call' || r.symbolType === 'Call') &&
                 r.strikePrice != null);
  if (!rows.length) return null;
  return rows
    .map(r => ({
      strike: r.strikePrice,
      delta:  typeof r.delta === 'number' ? r.delta : null,
    }))
    .sort((a, b) => a.strike - b.strike);
})()
"""

# Stage 1: expiration select (value like "2027-01-15-m") for V&G per-exp fallback
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

# Stage 1: underlying price (Angular rootScope → moneyness-median fallback)
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
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  const prices = grid._data
    .map(r => r.raw || r)
    .filter(r => typeof r.moneyness === 'number' &&
                 r.moneyness > 0.05 && r.moneyness < 0.95 && r.strikePrice > 0)
    .map(r => r.strikePrice / (1 - r.moneyness));
  if (!prices.length) return null;
  prices.sort((a, b) => a - b);
  return Math.round(prices[Math.floor(prices.length / 2)] * 100) / 100;
})()
"""

# Stage 2: stacked Options Prices — one strike, all expirations
STACKED_OPTIONS_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data
    .map(r => r.raw || r)
    .filter(r => r.optionType === 'Call' || r.symbolType === 'Call')
    .map(r => ({
      expiration_date: r.expirationDate || r.expirationDateString || r.expiration || null,
      dte:     typeof r.daysToExpiration === 'number' ? r.daysToExpiration : null,
      strike:  r.strikePrice,
      bid:     typeof r.bidPrice      === 'number' ? r.bidPrice      : null,
      ask:     typeof r.askPrice      === 'number' ? r.askPrice      : null,
      mid:     typeof r.midpoint      === 'number' ? r.midpoint      : null,
      last:    typeof r.lastPrice     === 'number' ? r.lastPrice     : null,
      volume:  typeof r.volume        === 'number' ? r.volume        : null,
      oi:      typeof r.openInterest  === 'number' ? r.openInterest  : null,
      delta:   typeof r.delta         === 'number' ? r.delta         : null,
      iv:      typeof r.volatility    === 'number' ? r.volatility    : null,
      moneyness: typeof r.moneyness   === 'number' ? r.moneyness     : null,
    }));
})()
"""

# Stage 2: stacked V&G — one strike, all expirations (may not be supported)
LOCK_STRIKE_VG_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data
    .map(r => r.raw || r)
    .filter(r => r.optionType === 'Call' || r.symbolType === 'Call')
    .map(r => ({
      expiration_date: r.expirationDate || r.expirationDateString || r.expiration || null,
      dte:      typeof r.daysToExpiration          === 'number' ? r.daysToExpiration          : null,
      strike:   r.strikePrice,
      itm_prob: typeof r.itmProbability            === 'number' ? r.itmProbability            : null,
      vol_oi:   typeof r.volumeOpenInterestRatio   === 'number' ? r.volumeOpenInterestRatio   : null,
      vega:     typeof r.vega                      === 'number' ? r.vega                      : null,
    }));
})()
"""

# V&G per-expiration fallback (no exp_date in row — caller supplies it)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _dte_to_date(dte):
    if dte is None:
        return None
    return (date.today() + timedelta(days=int(dte))).strftime("%Y-%m-%d")


def _fill_exp_dates(rows):
    """Fill expiration_date from DTE for rows where the JS field was null."""
    for r in rows:
        if not r.get("expiration_date") and r.get("dte") is not None:
            r["expiration_date"] = _dte_to_date(r["dte"])


def _pick_candidates(near_money_rows, user_strike=None):
    """
    Stage 1: determine which strikes to query in Stage 2.

    Returns sorted list of strike prices.
    Empty list means auto mode found no Delta>=0.80 in near-money view.

    Buffer rule: always add one strike below the lowest center and one
    above the highest center (from the visible near-money list), so that
    Delta drift across expiration dates is covered.

    Key invariant: 0.80 here is a Stage 1 filter only.  The caller
    (BarchartScraperService / LeapsRankingService) still applies the
    final 0.75-0.90 filter in Stage 2 / Ruby — this is a SEPARATE rule.
    """
    all_strikes = sorted({r["strike"] for r in near_money_rows if r.get("strike") is not None})

    if user_strike is not None:
        # Manual mode: user-specified center, skip Delta filter
        center_strikes = [float(user_strike)]
    else:
        # Auto mode: Delta >= 0.80 from Near the Money view
        center_strikes = sorted({
            r["strike"] for r in near_money_rows
            if r.get("delta") is not None and r["delta"] >= 0.80
        })
        if not center_strikes:
            return []

    candidates = set(center_strikes)

    # +/-1 buffer using the near-money strike list
    if all_strikes:
        lo = min(center_strikes)
        hi = max(center_strikes)
        below = [s for s in all_strikes if s < lo]
        if below:
            candidates.add(max(below))   # one strike deeper ITM
        above = [s for s in all_strikes if s > hi]
        if above:
            candidates.add(min(above))   # one strike less deep ITM

    return sorted(candidates)


def _merge_vg(opts_rows, vg_rows):
    """Join V&G rows into options rows by (strike, expiration_date)."""
    vg_idx = {(r["strike"], r.get("expiration_date")): r for r in (vg_rows or [])}
    return [
        {**row,
         "itm_probability": vg_idx.get((row["strike"], row.get("expiration_date")), {}).get("itm_prob"),
         "vol_oi_ratio":    vg_idx.get((row["strike"], row.get("expiration_date")), {}).get("vol_oi"),
         "vega":            vg_idx.get((row["strike"], row.get("expiration_date")), {}).get("vega")}
        for row in opts_rows
    ]



def _finalize(rows, underlying_price):
    """Normalize merged rows to the output schema."""
    result = []
    for r in rows:
        exp_date = r.get("expiration_date") or _dte_to_date(r.get("dte"))
        result.append({
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
        })
    return result


# ── Main ──────────────────────────────────────────────────────────────────────

async def main(symbol, user_strike=None):
    symbol = symbol.upper()

    # Navigate to base options page (Near the Money default view).
    # Serves as login check + Stage 1 data source.
    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=OPTIONS_SETTLE)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    # Login check: null grid data means session expired before even starting.
    near_money_rows = await cdp_eval(ws_url, NEAR_MONEY_JS)
    if near_money_rows is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)

    # Expiration select — kept for V&G per-exp fallback if stacked V&G is not supported.
    expirations = await cdp_eval(ws_url, EXPIRATIONS_JS) or []
    # Maps "2027-01-15" -> "2027-01-15-m" (the select option value)
    exp_value_map = {e["value"][:10]: e["value"] for e in expirations}
    first_exp_value = next(iter(exp_value_map.values()), None)

    # ── Stage 1: pick candidate strikes ──────────────────────────────────────
    candidate_strikes = _pick_candidates(near_money_rows, user_strike)
    if not candidate_strikes:
        # Auto mode: no Delta>=0.80 strikes visible in near-money view
        print(json.dumps({"status": "no_candidates"}))
        return

    # ── Stage 2: per candidate strike ────────────────────────────────────────
    all_opts_rows = []
    all_vg_rows   = []

    for strike in candidate_strikes:

        # ── Options Prices (stacked) ──────────────────────────────────────────
        opts_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/options"
            f"?view=stacked&strike={strike}"
        )
        await cdp_navigate(ws_url, opts_url, settle_ms=OPTIONS_SETTLE)
        await activate_target(target_id)

        opts_rows = await cdp_eval(ws_url, STACKED_OPTIONS_JS)
        if not opts_rows:
            print(json.dumps({
                "status":            "partial",
                "rows":              _finalize(all_opts_rows, underlying_price),
                "expired_at_strike": strike,
                "expired_layer":     "options_prices",
            }))
            return

        _fill_exp_dates(opts_rows)
        all_opts_rows.extend(opts_rows)

        # ── Volatility & Greeks ───────────────────────────────────────────────
        # V&G lock-by-strike (confirmed: ?expiration=seed&strike=X)
        if first_exp_value:
            vg_url = (
                f"https://www.barchart.com/stocks/quotes/{symbol}/volatility-greeks"
                f"?expiration={first_exp_value}&strike={strike}"
            )
            await cdp_navigate(ws_url, vg_url, settle_ms=VG_SETTLE)
            await activate_target(target_id)

            vg_rows = await cdp_eval(ws_url, LOCK_STRIKE_VG_JS)
            if not vg_rows:
                print(json.dumps({
                    "status":            "partial",
                    "rows":              _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                    "expired_at_strike": strike,
                    "expired_layer":     "volatility_greeks",
                }))
                return
            _fill_exp_dates(vg_rows)
            all_vg_rows.extend(vg_rows)

        await asyncio.sleep(0.8)


    merged = _merge_vg(all_opts_rows, all_vg_rows)

    print(json.dumps({
        "status":           "success",
        "rows":             _finalize(merged, underlying_price),
        "underlying_price": underlying_price,
    }))


if __name__ == "__main__":
    sym      = sys.argv[1] if len(sys.argv) > 1 else "NOK"
    u_strike = float(sys.argv[2]) if len(sys.argv) > 2 else None
    asyncio.run(main(sym, user_strike=u_strike))
