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
from datetime import date

import numpy as np
import requests
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
        )
    except Exception as exc:
        logger.error("fetch_option_detail error for %s: %s", ticker, exc)
        return jsonify(error=str(exc)), 422


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5050, debug=False)
