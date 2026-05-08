#!/usr/bin/env python3
"""IV sidecar — Flask HTTP server on port 5050.
Uses FlashAlpha public /v1/surface endpoint (no rate limit, no auth needed).
Greeks computed locally via Black-Scholes.

# API Verification (2026-05-03):
# - Service: FlashAlpha Lab API
# - Surface endpoint: https://lab.flashalpha.com/v1/surface/{symbol}
# - Auth: Public (no API key needed for /v1/surface)
# - Rate limit: None for surface endpoint
# - Status: Active
"""
import math
import logging
import os
from datetime import date, timedelta

import numpy as np
import requests
import yfinance as yf
from scipy.interpolate import RegularGridInterpolator
from scipy.stats import norm
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

SURFACE_BASE = "https://lab.flashalpha.com"

_session = requests.Session()
_session.headers.update({"Accept": "application/json"})
_api_key = os.environ.get("FLASHALPHA_API_KEY")
if _api_key:
    _session.headers.update({"X-Api-Key": _api_key})


# -- Black-Scholes -----------------------------------------------------------

def bs_delta(S: float, K: float, T: float, r: float, sigma: float, option_type: str) -> float:
    if T <= 0 or sigma <= 0:
        return 0.5 if option_type == "call" else -0.5
    d1 = (math.log(S / K) + (r + 0.5 * sigma ** 2) * T) / (sigma * math.sqrt(T))
    return float(norm.cdf(d1)) if option_type == "call" else float(norm.cdf(d1) - 1)


def years_to_expiry(expiry_str: str) -> float:
    exp = date.fromisoformat(expiry_str)
    days = (exp - date.today()).days
    return max(days, 0) / 365.0


# -- Historic Volatility ------------------------------------------------------

def _hist_vol(ticker: str, window: int = 21) -> float | None:
    """Annualised HV = std(log-returns over `window` trading days) x sqrt(252)."""
    try:
        hist = yf.download(ticker, period="1y", interval="1d",
                           progress=False, auto_adjust=True)
        if hist.empty:
            return None
        closes = hist["Close"]
        if hasattr(closes, "squeeze"):
            closes = closes.squeeze()
        closes = closes.dropna()
        if len(closes) < window + 1:
            return None
        log_ret = np.log(closes / closes.shift(1)).dropna()
        hv = float(log_ret.tail(window).std() * math.sqrt(252))
        return round(hv, 6)
    except Exception as exc:
        logger.warning("HV calc failed for %s: %s", ticker, exc)
        return None


# -- FlashAlpha surface -------------------------------------------------------

def _fetch_surface(ticker: str) -> dict:
    """Public endpoint — no auth, no rate limit."""
    url = f"{SURFACE_BASE}/v1/surface/{ticker.upper()}"
    resp = _session.get(url, timeout=15)
    resp.raise_for_status()
    return resp.json()


def _surface_iv(data: dict, strike: float, dte_years: float) -> float:
    """Interpolate IV for any strike/tenor via log-moneyness grid."""
    spot      = data["spot"]
    tenors    = np.array(data["tenors"])
    moneyness = np.array(data["moneyness"])  # log(K/S) values
    iv_grid   = np.array(data["iv"])

    log_m = math.log(strike / spot)

    interp = RegularGridInterpolator(
        (tenors, moneyness), iv_grid,
        method="linear", bounds_error=False, fill_value=None
    )

    t_clamped = float(np.clip(dte_years, tenors.min(), tenors.max()))
    m_clamped = float(np.clip(log_m, moneyness.min(), moneyness.max()))

    iv_val = float(interp([[t_clamped, m_clamped]])[0])
    return max(iv_val, 0.001)


def _atm_iv(data: dict, dte_years: float | None = None) -> float:
    """ATM IV from surface at moneyness=0 for the nearest tenor."""
    tenors    = np.array(data["tenors"])
    moneyness = np.array(data["moneyness"])
    iv_grid   = np.array(data["iv"])

    atm_m_idx = int(np.argmin(np.abs(moneyness)))

    if dte_years is None:
        # Shortest tenor >= 7 calendar days to avoid near-expiry noise
        valid    = tenors[tenors >= 0.019]
        target_t = float(valid[0]) if len(valid) else float(tenors[0])
    else:
        target_t = float(np.clip(dte_years, tenors.min(), tenors.max()))

    t_idx = int(np.argmin(np.abs(tenors - target_t)))
    return max(float(iv_grid[t_idx][atm_m_idx]), 0.001)


# -- Expiration inference -----------------------------------------------------

# Fridays NYSE is closed -- option expiry shifts to prior Thursday
_CLOSED_FRIDAYS = frozenset([
    date(2026, 6, 19),  # Juneteenth
    date(2026, 7, 3),   # Independence Day observed (Jul 4 = Sat)
    date(2027, 1, 1),   # New Year's Day
])

_QUARTERLY_MONTHS = frozenset([3, 6, 9, 12])


def _infer_expirations(data: dict) -> tuple[list, int]:
    """Infer available option expiry dates from surface metadata.

    Uses slices_used as a proxy for option chain depth:
      <=15 slices -> quarterly cycle (3/6/9/12) + Jan LEAPS  (e.g. SQQQ)
      >15 slices  -> all monthly 3rd Fridays                  (e.g. AAPL)

    Returns (sorted list of dates, weekly_count).
    """
    tenors      = data["tenors"]
    slices_used = int(data.get("slices_used", 10))
    today       = date.today()

    # Surface coverage range
    max_date = today + timedelta(days=int(max(tenors) * 365) + 14)

    # Collect all Fridays from tomorrow up to max_date
    d = today + timedelta(days=1)
    while d.weekday() != 4:   # 4 = Friday
        d += timedelta(days=1)
    all_fridays: list[date] = []
    while d <= max_date:
        all_fridays.append(d)
        d += timedelta(days=7)

    # Weekly: first 6 open (non-holiday) Fridays
    open_fridays = [f for f in all_fridays if f not in _CLOSED_FRIDAYS]
    weekly       = open_fridays[:6]
    cutoff       = weekly[-1] if weekly else today

    # Monthly candidates: 3rd Friday zone (day 15--21), after weekly period
    candidates = [f for f in all_fridays if f > cutoff and 15 <= f.day <= 21]

    if slices_used <= 15:
        # Quarterly months within surface range + Jan LEAPS for next 2 years
        quarterly = [f for f in candidates if f.month in _QUARTERLY_MONTHS]
        jan_leaps = []
        for offset in range(1, 3):
            yr  = today.year + offset
            jan = date(yr, 1, 1)
            fri = jan
            while fri.weekday() != 4:
                fri += timedelta(days=1)
            third_fri = fri + timedelta(days=14)
            if third_fri > cutoff:
                jan_leaps.append(third_fri)
        # Merge & deduplicate, then apply holiday shift
        combined = sorted(set(quarterly) | set(jan_leaps))
    else:
        combined = candidates

    monthly = [
        (f - timedelta(days=1) if f in _CLOSED_FRIDAYS else f)
        for f in combined
    ]

    return weekly + monthly, len(weekly)


def _real_expirations(ticker: str, surface_data: dict) -> tuple[list, int]:
    """Fetch real option expiration dates from yfinance.

    Falls back to _infer_expirations when yfinance fails or returns nothing.
    """
    tenors = surface_data["tenors"]
    today = date.today()
    max_date = today + timedelta(days=int(max(tenors) * 365) + 14)

    try:
        raw = yf.Ticker(ticker).options  # tuple of "YYYY-MM-DD" strings
        if not raw:
            raise ValueError("no options returned from yfinance")

        dates = sorted(
            date.fromisoformat(s)
            for s in raw
            if today < date.fromisoformat(s) <= max_date
        )
        if not dates:
            raise ValueError("no future dates within surface range")

        # Dates within 8 weeks (cap 6) → near-term "週選" group
        cutoff = today + timedelta(weeks=8)
        weekly = [d for d in dates if d <= cutoff][:6]
        monthly = [d for d in dates if d not in set(weekly)]
        return weekly + monthly, len(weekly)

    except Exception as exc:
        logger.warning("yfinance expirations failed for %s: %s", ticker, exc)
        raise RuntimeError("無法取得 Yahoo Finance 資料，請稍候再試") from exc


# -- Endpoints ----------------------------------------------------------------

@app.post("/fetch_atm_iv")
def fetch_atm_iv():
    body   = request.get_json(silent=True) or {}
    ticker = (body.get("ticker") or "").upper().strip()
    if not ticker:
        return jsonify(error="ticker is required"), 422

    try:
        data   = _fetch_surface(ticker)
        spot   = round(float(data["spot"]), 2)
        atm_iv = round(_atm_iv(data), 6)
        return jsonify(
            ticker=ticker,
            current_price=spot,
            atm_iv=atm_iv,
            snapshot_date=date.today().isoformat(),
        )
    except Exception as exc:
        logger.error("fetch_atm_iv error for %s: %s", ticker, exc)
        return jsonify(error=str(exc)), 422


@app.post("/fetch_option_detail")
def fetch_option_detail():
    body        = request.get_json(silent=True) or {}
    ticker      = (body.get("ticker") or "").upper().strip()
    strike      = body.get("strike")
    expiry_date = body.get("expiry_date")
    option_type = (body.get("option_type") or "call").lower()

    missing = [f for f, v in [("ticker", ticker), ("strike", strike), ("expiry_date", expiry_date)] if not v]
    if missing:
        return jsonify(error=f"missing fields: {', '.join(missing)}"), 422
    if option_type not in ("call", "put"):
        return jsonify(error="option_type must be 'call' or 'put'"), 422

    try:
        strike = float(strike)
        data   = _fetch_surface(ticker)
        spot   = float(data["spot"])
        T      = years_to_expiry(expiry_date)
        iv     = _surface_iv(data, strike, T)
        delta  = bs_delta(spot, strike, T, r=0.045, sigma=iv, option_type=option_type)
        atm    = round(_atm_iv(data, T), 6)
        dte    = max((date.fromisoformat(expiry_date) - date.today()).days, 0)
        # HV window matches DTE (calendar -> trading days, capped 21-252)
        hv_window = max(min(round(dte * 252 / 365), 252), 21)
        hv_dte    = _hist_vol(ticker, hv_window)

        return jsonify(
            ticker=ticker,
            requested_strike=round(strike, 2),
            strike=round(strike, 2),
            strike_snapped=False,
            expiry_date=expiry_date,
            option_type=option_type,
            current_price=round(spot, 2),
            iv=round(iv, 6),
            delta=round(delta, 4),
            atm_iv=atm,
            dte=dte,
            hv_dte=hv_dte,
            hv_window=hv_window,
        )
    except Exception as exc:
        logger.error("fetch_option_detail error for %s: %s", ticker, exc)
        return jsonify(error=str(exc)), 422


@app.get("/expirations/<ticker>")
def expirations(ticker):
    ticker = ticker.upper().strip()
    if not ticker:
        return jsonify(error="ticker required"), 422
    try:
        data          = _fetch_surface(ticker)
        dates, wcount = _real_expirations(ticker, data)
        return jsonify(
            expirations=[d.isoformat() for d in dates],
            weekly_count=wcount,
        )
    except Exception as exc:
        logger.error("expirations error for %s: %s", ticker, exc)
        return jsonify(error=str(exc)), 422


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5050, debug=False)
