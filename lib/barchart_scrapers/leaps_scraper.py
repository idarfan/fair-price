"""
Barchart LEAPS option chain scraper — Stacked view strategy (Phase G).

Two-stage approach:
  Stage 1  Load Near the Money view:
           • read all visible strikes + Deltas
           • determine candidate strikes (Delta>=0.60, or user-supplied center)
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
  no_candidates → {"status":"no_candidates"}   # auto mode: no Delta>=0.60 in near-money
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
STAGE1_SETTLE  = 5000   # Stage 1 (NTM) fixed sleep — no polling, must be long enough
OPTIONS_SETTLE = 1500   # Stage 2 opts initial settle; _wait_for_grid polls up to 30 s
VG_SETTLE      = 1500   # Stage 2 V&G initial settle; _wait_for_grid polls up to 25 s
LEAPS_MIN_DTE  = 364    # chain_snapshot must be built from a LEAPS-dated expiration (see fix below),
                        # matches LeapsRankingService::MIN_DTE

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


# Session-expiry positive detection — same modal logic as technical-analysis page
# bc-overlay-modal-wrapper always exists; login keywords appear only when session expires
SESSION_EXPIRED_JS = """
(() => {
  const modal = document.querySelector('div.bc-overlay-modal-wrapper');
  if (!modal) return false;
  const text = modal.innerText.trim().toLowerCase();
  return text.includes('sign in') || text.includes('log in') ||
         text.includes('welcome to barchart') || text.includes('continue with google');
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


def _pick_candidates(near_money_rows, user_strike=None, underlying_price=None):
    """
    Stage 1: determine which strikes to query in Stage 2.

    Returns sorted list of strike prices.
    Empty list means auto mode found no qualifying strike in near-money view.

    Buffer rule: always add one strike below the lowest center and one
    above the highest center (from the visible near-money list), so that
    Delta drift across expiration dates is covered.

    Key invariant: 0.60 here is a Stage 1 filter only.  The caller
    (BarchartScraperService / LeapsRankingService) still applies the
    final 0.60-0.90 filter in Stage 2 / Ruby — this is a SEPARATE rule.

    BUG FIX (reported 2026-07-09, NOK strike 7): the Near the Money view reads
    Greeks from the NEAREST expiration (short DTE). For deep ITM strikes with
    little/no recent volume at that near expiration, Barchart does not compute
    Delta/IV at all and reports them as 0 — not "Delta is genuinely low", but
    "Delta was never calculated". Filtering on `delta >= 0.60` alone silently
    drops these strikes from Stage 1, even though the SAME strike has a
    perfectly good Delta (0.85+) at the LEAPS-dated expirations Stage 2 would
    have fetched. A row with delta == 0 AND iv == 0 is treated as "Greeks not
    computed" and falls back to a plain intrinsic-value ITM check instead of
    being excluded outright.
    """
    all_strikes = sorted({r["strike"] for r in near_money_rows if r.get("strike") is not None})

    if user_strike is not None:
        # Manual mode: user-specified center, skip Delta filter
        center_strikes = [float(user_strike)]
    else:
        def _qualifies(row):
            delta = row.get("delta")
            if delta is not None and delta >= 0.60:
                return True
            greeks_computed = delta not in (None, 0) or row.get("iv") not in (None, 0)
            if greeks_computed:
                return False
            # Greeks missing (delta == 0 and iv == 0): fall back to intrinsic
            # value — a call strike below the underlying price is in-the-money
            # regardless of what Barchart's (uncomputed) Delta field shows.
            return underlying_price is not None and row["strike"] < underlying_price

        # Auto mode: Delta >= 0.60 from Near the Money view, with the
        # missing-Greeks fallback above.
        center_strikes = sorted({
            r["strike"] for r in near_money_rows
            if r.get("strike") is not None and _qualifies(r)
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



async def _wait_for_grid(ws_url, js_expr, max_wait_s=30, poll_s=0.5):
    """
    Poll for bc-data-grid._data to be non-null after navigation.

    Returns:
      list (possibly [])  — grid mounted, _data assigned (may be empty)
      None                — timed out; caller must check session expiry
    """
    deadline = asyncio.get_event_loop().time() + max_wait_s
    while asyncio.get_event_loop().time() < deadline:
        result = await cdp_eval(ws_url, js_expr)
        if result is not None:
            return result
        await asyncio.sleep(poll_s)
    return None


async def _confirm_empty(ws_url, js_expr, delay_s=1.5):
    """
    Stability check: re-evaluate after delay_s to confirm [] is real, not mid-load.

    Returns the second evaluation result:
      list with rows  — data appeared; use it
      []              — confirmed empty
      None            — grid unmounted (treat as timeout)
    """
    await asyncio.sleep(delay_s)
    return await cdp_eval(ws_url, js_expr)


# ── Main ──────────────────────────────────────────────────────────────────────

async def main(symbol, user_strike=None):
    symbol = symbol.upper()

    # prepare_page finds the tab but skips navigation when Chrome is already on
    # any /options URL (e.g. ?view=stacked&strike=12 from a previous query).
    # Force-navigate to Near the Money SBS view so Stage 1 always reads
    # multi-strike data, not whatever filtered view Chrome last showed.
    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=500)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    ntm_url = f"https://www.barchart.com/stocks/quotes/{symbol}/options?moneyness=10"
    await cdp_navigate(ws_url, ntm_url, settle_ms=2000)  # brief settle; poll does the rest
    await activate_target(target_id)

    # Poll up to 30 s for the NTM grid to populate (page may take longer than fixed sleep)
    near_money_rows = await _wait_for_grid(ws_url, NEAR_MONEY_JS, max_wait_s=30)
    if near_money_rows is None:
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)

    # Expiration select — kept for V&G per-exp fallback if stacked V&G is not supported.
    expirations = await cdp_eval(ws_url, EXPIRATIONS_JS) or []
    # Maps "2027-01-15" -> "2027-01-15-m" (the select option value)
    exp_value_map = {e["value"][:10]: e["value"] for e in expirations}
    first_exp_value = next(iter(exp_value_map.values()), None)

    # ── Build chain_snapshot from a LEAPS-dated expiration (root-cause fix) ───
    # BUG (reported 2026-07-07, NOK): chain_snapshot was built from `near_money_rows`,
    # which reflects whatever NEAR-TERM expiration Barchart defaults to for
    # `?moneyness=10` (no explicit `expiration=` param — confirmed via live DOM
    # inspection). Near-term strike ladders are NOT the same set as LEAPS
    # (far-dated) ladders: e.g. NOK's nearest weekly lists $6/7/8/8.5/9...16.5,
    # while its 2028-01-21 LEAPS expiration lists $2/2.5/3/3.5/4/4.5/5/5.5/7/10/
    # 12/15/17/20/22/25/27/30/32 — different increments, different deep-ITM/OTM
    # strikes present. Validating a LEAPS user_strike against the near-term
    # expiration's strikes is validating against the wrong chain entirely; a
    # legitimate deep-ITM LEAPS strike (e.g. $7, Delta ~0.85, real OI) can be
    # absent from the near-term ladder purely because of this expiration
    # mismatch, independent of the moneyness window width.
    #
    # Fix: find the nearest expiration with DTE >= LEAPS_MIN_DTE and read ITS
    # full strike list (`moneyness=100` empirically returns the complete listed
    # ladder for whichever expiration is loaded — verified live, larger values
    # plateau at the same set) — that is the chain a LEAPS user_strike actually
    # refers to.
    leaps_exp_date = None
    for date_str in sorted(exp_value_map):
        y, m, d = (int(x) for x in date_str.split("-"))
        if (date(y, m, d) - date.today()).days >= LEAPS_MIN_DTE:
            leaps_exp_date = date_str
            break

    if leaps_exp_date:
        leaps_chain_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/options"
            f"?moneyness=100&expiration={exp_value_map[leaps_exp_date]}"
        )
        await cdp_navigate(ws_url, leaps_chain_url, settle_ms=2000)
        await activate_target(target_id)
        leaps_chain_rows = await _wait_for_grid(ws_url, NEAR_MONEY_JS, max_wait_s=30) or []
        all_strikes = sorted({r["strike"] for r in leaps_chain_rows if r.get("strike") is not None})
    else:
        # No expiration far enough out for this symbol (rare) — fall back to
        # the near-term near-money list rather than an empty chain_snapshot.
        all_strikes = sorted({
            r.get("strike") or r.get("strikePrice")
            for r in near_money_rows
            if (r.get("strike") or r.get("strikePrice")) is not None
        })

    chain_snapshot = {"strikes": all_strikes, "spot_price": underlying_price}

    # ── Stage 1 post-check: validate user_strike against actual chain ─────────
    if user_strike is not None and all_strikes:
        min_s = min(all_strikes)
        max_s = max(all_strikes)
        # Tolerance = average spacing between strikes (or 10% of min if only one strike)
        if len(all_strikes) > 1:
            spacings = [b - a for a, b in zip(all_strikes, all_strikes[1:])]
            tol = sum(spacings) / len(spacings)
        else:
            tol = min_s * 0.10
        if user_strike < (min_s - tol) or user_strike > (max_s + tol):
            spot_str = f"${underlying_price:.2f}" if underlying_price else "不明"
            print(json.dumps({
                "status":         "invalid_strike",
                "message":        (
                    f"Strike {user_strike} 不在 {symbol} 的履約價範圍"
                    f"（實際範圍 ${min_s:.2f}–${max_s:.2f}，現價 {spot_str}），請重新輸入"
                ),
                "chain_snapshot": chain_snapshot,
                "rows":           [],
            }))
            return

    # ── Stage 1: pick candidate strikes ──────────────────────────────────────
    candidate_strikes = _pick_candidates(near_money_rows, user_strike, underlying_price)
    if not candidate_strikes:
        # Auto mode: no Delta>=0.60 strikes visible in near-money view
        print(json.dumps({"status": "no_candidates", "chain_snapshot": chain_snapshot}))
        return

    # ── Stage 2: per candidate strike ────────────────────────────────────────
    all_opts_rows   = []
    all_vg_rows     = []
    skipped_strikes = []   # strikes skipped due to confirmed-empty grid

    for strike in candidate_strikes:

        # ── Options Prices (stacked) ──────────────────────────────────────────
        opts_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/options"
            f"?view=stacked&strike={strike}"
        )
        await cdp_navigate(ws_url, opts_url, settle_ms=OPTIONS_SETTLE)
        await activate_target(target_id)

        opts_rows = await _wait_for_grid(ws_url, STACKED_OPTIONS_JS, max_wait_s=30)

        if opts_rows is None:
            # Grid not mounted after 30 s — classify: session expired vs page timeout
            is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
            print(json.dumps({
                "status":            "partial",
                "rows":              _finalize(all_opts_rows, underlying_price),
                "expired_at_strike": strike,
                "expired_layer":     "options_prices",
                "reason":            "session_expired" if is_expired else "page_load_timeout",
                "skipped_strikes":   skipped_strikes,
                "chain_snapshot":    chain_snapshot,
            }))
            return

        if not opts_rows:
            # Grid mounted but zero Call rows — stability check before skipping
            confirmed = await _confirm_empty(ws_url, STACKED_OPTIONS_JS)
            if confirmed:
                opts_rows = confirmed          # data appeared after 1.5 s, use it
            elif confirmed is None:
                # Grid unmounted during stability check — treat as timeout
                is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
                print(json.dumps({
                    "status":            "partial",
                    "rows":              _finalize(all_opts_rows, underlying_price),
                    "expired_at_strike": strike,
                    "expired_layer":     "options_prices",
                    "reason":            "session_expired" if is_expired else "page_load_timeout",
                    "skipped_strikes":   skipped_strikes,
                    "chain_snapshot":    chain_snapshot,
                }))
                return
            else:
                # Still [] after stability check — genuinely no Call rows, skip with log
                import sys as _sys
                _sys.stderr.write(
                    f"[leaps] strike={strike} options_prices: confirmed empty after stability "
                    f"check, skipping (not a session issue)\n"
                )
                skipped_strikes.append({"strike": strike, "layer": "options_prices"})
                await asyncio.sleep(0.8)
                continue

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

            vg_rows = await _wait_for_grid(ws_url, LOCK_STRIKE_VG_JS, max_wait_s=25)

            if vg_rows is None:
                is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
                print(json.dumps({
                    "status":            "partial",
                    "rows":              _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                    "expired_at_strike": strike,
                    "expired_layer":     "volatility_greeks",
                    "reason":            "session_expired" if is_expired else "page_load_timeout",
                    "skipped_strikes":   skipped_strikes,
                    "chain_snapshot":    chain_snapshot,
                }))
                return

            if not vg_rows:
                # Stability check for V&G empty
                confirmed_vg = await _confirm_empty(ws_url, LOCK_STRIKE_VG_JS)
                if confirmed_vg:
                    vg_rows = confirmed_vg
                elif confirmed_vg is None:
                    is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
                    print(json.dumps({
                        "status":            "partial",
                        "rows":              _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                        "expired_at_strike": strike,
                        "expired_layer":     "volatility_greeks",
                        "reason":            "session_expired" if is_expired else "page_load_timeout",
                        "skipped_strikes":   skipped_strikes,
                        "chain_snapshot":    chain_snapshot,
                    }))
                    return
                else:
                    # V&G confirmed empty — not fatal (V&G optional), skip with log
                    import sys as _sys
                    _sys.stderr.write(
                        f"[leaps] strike={strike} volatility_greeks: confirmed empty after "
                        f"stability check, skipping V&G for this strike\n"
                    )
                    skipped_strikes.append({"strike": strike, "layer": "volatility_greeks"})
                    await asyncio.sleep(0.8)
                    continue

            _fill_exp_dates(vg_rows)
            all_vg_rows.extend(vg_rows)

        await asyncio.sleep(0.8)


    merged = _merge_vg(all_opts_rows, all_vg_rows)

    print(json.dumps({
        "status":           "success",
        "rows":             _finalize(merged, underlying_price),
        "underlying_price": underlying_price,
        "skipped_strikes":  skipped_strikes,
        "chain_snapshot":   chain_snapshot,
    }))


if __name__ == "__main__":
    sym      = sys.argv[1] if len(sys.argv) > 1 else "NOK"
    u_strike = float(sys.argv[2]) if len(sys.argv) > 2 else None
    asyncio.run(main(sym, user_strike=u_strike))
