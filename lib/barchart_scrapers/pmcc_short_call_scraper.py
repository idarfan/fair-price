"""
Barchart PMCC Short Call scraper — three-expiration snapshot (PMCC v3 spec §6).

Reads the Expiration dropdown on the Options Prices page, takes the first
three entries (DOM order, already date-ascending — "moneyness=100" on each
expiration URL returns the full listed Call strike ladder for that date).
For each of the three expirations:
  * Options Prices  ?expiration={exp}&moneyness=100  -> full Call strike ladder
  * Volatility & Greeks  ?expiration={exp}            -> merge by (strike, expiration_date)

No Delta filtering happens here — spec §6/§7: "不在 Python 硬濾，交 Ruby 處理
（避免誤刪）". PmccRankingService (Ruby) applies the 0.15-0.40 grade filter.
This scraper's only job is "get every Call row for the first three
expirations, as completely as possible."

mid is passed through as Barchart's raw midpoint field (may be null) —
deciding the final mid_price (§2.1: midpoint 原值 → fallback (bid+ask)/2 →
null) happens in Ruby (BarchartScraperService#persist_pmcc_short_calls),
not here.

Usage:  python3 pmcc_short_call_scraper.py SYMBOL

Output JSON (stdout):
  success       -> {"status":"success","rows":[...],"underlying_price":N,
                     "expirations":[...],"skipped_expirations":[...]}
  partial       -> {"status":"partial","rows":[...],"expired_at_expiration":"YYYY-MM-DD",
                     "expired_layer":"options_prices"|"volatility_greeks",
                     "reason":"session_expired"|"page_load_timeout",
                     "skipped_expirations":[...]}
  no_candidates -> {"status":"no_candidates"}   # expiration dropdown empty/unreadable
  expired       -> {"status":"barchart_session_expired"}
  error         -> {"status":"error","error":"..."}
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, cdp_navigate, activate_target

TARGET_PATH    = "options"
STAGE1_SETTLE  = 3000
OPTIONS_SETTLE = 1500
VG_SETTLE      = 1500
EXP_COUNT      = 3   # spec §3: 三時段 = 前三個到期日（DOM 順序，已按日期升序）

# ── Stage 1: expiration dropdown ──────────────────────────────────────────────
# NOTE: spec §6 provided a `select[name="expiration"]` snippet flagged "需實測".
# Live-verified (2026-07-11, NOK options page via Playwright MCP browser_evaluate)
# that snippet matches the WRONG element — a page-navigation dropdown (Options/
# V&G/Unusual Activity/...) whose option values are URL paths that also happen
# to contain a "20\\d{2}-" date substring, not the actual expiration selector.
# Reused leaps_scraper.py's EXPIRATIONS_JS selector logic instead (already
# live-verified for this exact page type): live-checked again just now,
# correctly returns 18 options in date-ascending order starting
# ["2026-07-17-m","2026-07-24-w","2026-07-31-w",...] — matches spec §3's example.
EXPIRATIONS_JS = """
(() => {
  const sel = [...document.querySelectorAll('select')].find(
    s => s.className.includes('ng-') && s.options.length > 3 &&
         [...s.options].some(o => /\\d{4}-\\d{2}-\\d{2}/.test(o.value))
  );
  if (!sel) return null;
  return [...sel.options].map(o => o.value.trim()).filter(v => /\\d{4}-\\d{2}-\\d{2}/.test(v));
})()
"""

# Stage 1: underlying price — same Angular rootScope probe as leaps_scraper
# (same page type, same page structure).
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

# Stage 2: Options Prices — one expiration, full Call strike ladder (spec §6 verbatim)
OPTIONS_PRICES_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data.map(r=>r.raw||r).filter(r=>r.optionType==='Call'||r.symbolType==='Call')
    .map(r=>({
      expiration_date: r.expirationDate||r.expirationDateString||null,
      dte: typeof r.daysToExpiration==='number'?r.daysToExpiration:null,
      strike: r.strikePrice,
      bid: typeof r.bidPrice==='number'?r.bidPrice:null,
      ask: typeof r.askPrice==='number'?r.askPrice:null,
      mid: typeof r.midpoint==='number'?r.midpoint:null,
      last: typeof r.lastPrice==='number'?r.lastPrice:null,
      volume: typeof r.volume==='number'?r.volume:null,
      oi: typeof r.openInterest==='number'?r.openInterest:null,
      oi_chg: typeof r.openInterestChange==='number'?r.openInterestChange:(typeof r.oiChange==='number'?r.oiChange:null),
      moneyness: typeof r.moneyness==='number'?r.moneyness:null,
      delta: typeof r.delta==='number'?r.delta:null,
      iv: typeof r.volatility==='number'?r.volatility:null,
      change: typeof r.priceChange==='number'?r.priceChange:null,
      pct_change: typeof r.percentChange==='number'?r.percentChange:null,
    }));
})()
"""

# Stage 2: Volatility & Greeks — one expiration, full Call strike ladder (spec §6 verbatim)
VG_JS = """
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid||!grid._data) return null;
  return grid._data.map(r=>r.raw||r).filter(r=>r.optionType==='Call'||r.symbolType==='Call')
    .map(r=>({
      expiration_date: r.expirationDate||r.expirationDateString||null,
      strike: r.strikePrice,
      theoretical: typeof r.theoretical==='number'?r.theoretical:null,
      iv: typeof r.volatility==='number'?r.volatility:null,
      delta: typeof r.delta==='number'?r.delta:null,
      gamma: typeof r.gamma==='number'?r.gamma:null,
      theta: typeof r.theta==='number'?r.theta:null,
      vega: typeof r.vega==='number'?r.vega:null,
      rho: typeof r.rho==='number'?r.rho:null,
      itm_prob: typeof r.itmProbability==='number'?r.itmProbability:null,
      vol_oi: typeof r.volumeOpenInterestRatio==='number'?r.volumeOpenInterestRatio:null,
    }));
})()
"""

# Session-expiry positive detection — same modal logic as leaps_scraper/technical-analysis
SESSION_EXPIRED_JS = """
(() => {
  const modal = document.querySelector('div.bc-overlay-modal-wrapper');
  if (!modal) return false;
  const text = modal.innerText.trim().toLowerCase();
  return text.includes('sign in') || text.includes('log in') ||
         text.includes('welcome to barchart') || text.includes('continue with google');
})()
"""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _fill_exp_date(rows, exp_key):
    """Force expiration_date = exp_key when the JS field came back null.

    exp_key is derived from the URL param we navigated with, so it is
    authoritative regardless of whether Barchart's row data echoes it back —
    the (strike, expiration_date) merge key must not depend on an
    optional/unreliable field.
    """
    for r in rows:
        if not r.get("expiration_date"):
            r["expiration_date"] = exp_key


def _merge_vg(opts_rows, vg_rows):
    """Join V&G rows into options rows by (strike, expiration_date).

    V&G's own iv/delta are the Greeks page's numbers (lock-by-expiration,
    same guarantee LEAPS' lock-by-strike merge relies on) — prefer them over
    the Options Prices page's iv/delta when both are present.
    """
    vg_idx = {(r["strike"], r.get("expiration_date")): r for r in (vg_rows or [])}
    merged = []
    for row in opts_rows:
        vg = vg_idx.get((row["strike"], row.get("expiration_date")), {})
        merged.append({
            **row,
            "theoretical_price": vg.get("theoretical"),
            "gamma":             vg.get("gamma"),
            "theta":             vg.get("theta"),
            "rho":               vg.get("rho"),
            "itm_probability":   vg.get("itm_prob"),
            "vol_oi_ratio":      vg.get("vol_oi"),
            "iv":    vg.get("iv")    if vg.get("iv")    is not None else row.get("iv"),
            "delta": vg.get("delta") if vg.get("delta") is not None else row.get("delta"),
        })
    return merged


def _finalize(rows, underlying_price):
    """Normalize merged rows to the output schema (aligns with §5 DDL field names)."""
    result = []
    for r in rows:
        result.append({
            "expiration_date":   r.get("expiration_date"),
            "dte":               r.get("dte"),
            "strike":            r.get("strike"),
            "option_type":       "Call",
            "bid":               r.get("bid"),
            "ask":               r.get("ask"),
            "mid":               r.get("mid"),
            "last_price":        r.get("last"),
            "moneyness":         r.get("moneyness"),
            "underlying_price":  underlying_price,
            "change":            r.get("change"),
            "percent_change":    r.get("pct_change"),
            "volume":            r.get("volume"),
            "open_interest":     r.get("oi"),
            "oi_change":         r.get("oi_chg"),
            "vol_oi_ratio":      r.get("vol_oi_ratio"),
            "iv":                r.get("iv"),
            "delta":             r.get("delta"),
            "gamma":             r.get("gamma"),
            "theta":             r.get("theta"),
            "vega":              r.get("vega"),
            "rho":               r.get("rho"),
            "theoretical_price": r.get("theoretical_price"),
            "itm_probability":   r.get("itm_probability"),
        })
    return result


async def _wait_for_grid(ws_url, js_expr, max_wait_s=30, poll_s=0.5):
    """Poll for bc-data-grid._data to be non-null after navigation.

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
    """Stability check: re-evaluate after delay_s to confirm [] is real, not mid-load."""
    await asyncio.sleep(delay_s)
    return await cdp_eval(ws_url, js_expr)


# ── Main ──────────────────────────────────────────────────────────────────────

async def main(symbol):
    symbol = symbol.upper()

    target_id, ws_url = await prepare_page(symbol, TARGET_PATH, settle_ms=500)
    if not target_id:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    options_url = f"https://www.barchart.com/stocks/quotes/{symbol}/options"
    await cdp_navigate(ws_url, options_url, settle_ms=STAGE1_SETTLE)
    await activate_target(target_id)

    underlying_price = await cdp_eval(ws_url, UNDERLYING_JS)

    expirations = await cdp_eval(ws_url, EXPIRATIONS_JS) or []
    selected_expirations = expirations[:EXP_COUNT]

    if not selected_expirations:
        print(json.dumps({"status": "no_candidates"}))
        return

    all_opts_rows       = []
    all_vg_rows         = []
    skipped_expirations = []

    for exp_value in selected_expirations:
        exp_key = exp_value[:10]  # "2026-07-17" from e.g. "2026-07-17-m" / "-w"

        # ── Options Prices ────────────────────────────────────────────────────
        opts_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/options"
            f"?expiration={exp_value}&moneyness=100"
        )
        await cdp_navigate(ws_url, opts_url, settle_ms=OPTIONS_SETTLE)
        await activate_target(target_id)

        opts_rows = await _wait_for_grid(ws_url, OPTIONS_PRICES_JS, max_wait_s=30)

        if opts_rows is None:
            is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
            print(json.dumps({
                "status":                "partial",
                "rows":                  _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                "expired_at_expiration": exp_key,
                "expired_layer":         "options_prices",
                "reason":                "session_expired" if is_expired else "page_load_timeout",
                "skipped_expirations":   skipped_expirations,
            }))
            return

        if not opts_rows:
            confirmed = await _confirm_empty(ws_url, OPTIONS_PRICES_JS)
            if confirmed:
                opts_rows = confirmed
            elif confirmed is None:
                is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
                print(json.dumps({
                    "status":                "partial",
                    "rows":                  _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                    "expired_at_expiration": exp_key,
                    "expired_layer":         "options_prices",
                    "reason":                "session_expired" if is_expired else "page_load_timeout",
                    "skipped_expirations":   skipped_expirations,
                }))
                return
            else:
                import sys as _sys
                _sys.stderr.write(
                    f"[pmcc] expiration={exp_key} options_prices: confirmed empty after "
                    f"stability check, skipping (not a session issue)\n"
                )
                skipped_expirations.append({"expiration": exp_key, "layer": "options_prices"})
                await asyncio.sleep(0.8)
                continue

        _fill_exp_date(opts_rows, exp_key)
        all_opts_rows.extend(opts_rows)

        # ── Volatility & Greeks ──────────────────────────────────────────────
        vg_url = (
            f"https://www.barchart.com/stocks/quotes/{symbol}/volatility-greeks"
            f"?expiration={exp_value}"
        )
        await cdp_navigate(ws_url, vg_url, settle_ms=VG_SETTLE)
        await activate_target(target_id)

        vg_rows = await _wait_for_grid(ws_url, VG_JS, max_wait_s=25)

        if vg_rows is None:
            is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
            print(json.dumps({
                "status":                "partial",
                "rows":                  _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                "expired_at_expiration": exp_key,
                "expired_layer":         "volatility_greeks",
                "reason":                "session_expired" if is_expired else "page_load_timeout",
                "skipped_expirations":   skipped_expirations,
            }))
            return

        if not vg_rows:
            confirmed_vg = await _confirm_empty(ws_url, VG_JS)
            if confirmed_vg:
                vg_rows = confirmed_vg
            elif confirmed_vg is None:
                is_expired = await cdp_eval(ws_url, SESSION_EXPIRED_JS) or False
                print(json.dumps({
                    "status":                "partial",
                    "rows":                  _finalize(_merge_vg(all_opts_rows, all_vg_rows), underlying_price),
                    "expired_at_expiration": exp_key,
                    "expired_layer":         "volatility_greeks",
                    "reason":                "session_expired" if is_expired else "page_load_timeout",
                    "skipped_expirations":   skipped_expirations,
                }))
                return
            else:
                # V&G optional — not fatal, skip with log (same posture as leaps_scraper)
                import sys as _sys
                _sys.stderr.write(
                    f"[pmcc] expiration={exp_key} volatility_greeks: confirmed empty after "
                    f"stability check, skipping V&G for this expiration\n"
                )
                skipped_expirations.append({"expiration": exp_key, "layer": "volatility_greeks"})
                await asyncio.sleep(0.8)
                continue

        _fill_exp_date(vg_rows, exp_key)
        all_vg_rows.extend(vg_rows)

        await asyncio.sleep(0.8)

    merged = _merge_vg(all_opts_rows, all_vg_rows)

    print(json.dumps({
        "status":              "success",
        "rows":                _finalize(merged, underlying_price),
        "underlying_price":    underlying_price,
        "expirations":         [e[:10] for e in selected_expirations],
        "skipped_expirations": skipped_expirations,
    }))


if __name__ == "__main__":
    sym = sys.argv[1] if len(sys.argv) > 1 else "NOK"
    asyncio.run(main(sym))
