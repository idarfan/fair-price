#!/usr/bin/env python3
"""IV sidecar — Flask HTTP server on port 5050.
Provides yfinance-based option data to Rails backend.
"""
import math
import logging
from datetime import date

import yfinance as yf
import numpy as np
from scipy.stats import norm
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


# ── Black-Scholes delta ─────────────────────────────────────────────────────

def bs_delta(S: float, K: float, T: float, r: float, sigma: float, option_type: str) -> float:
    """Black-Scholes delta. T in years."""
    if T <= 0 or sigma <= 0:
        return 0.5 if option_type == "call" else -0.5
    d1 = (math.log(S / K) + (r + 0.5 * sigma ** 2) * T) / (sigma * math.sqrt(T))
    if option_type == "call":
        return float(norm.cdf(d1))
    return float(norm.cdf(d1) - 1)


def years_to_expiry(expiry_str: str) -> float:
    """Days between today and expiry_str (YYYY-MM-DD), divided by 252."""
    exp = date.fromisoformat(expiry_str)
    days = (exp - date.today()).days
    return max(days, 0) / 252.0


# ── Helpers ─────────────────────────────────────────────────────────────────

def _get_chain(tk: yf.Ticker, expiry: str, option_type: str):
    """Return calls or puts DataFrame for given expiry."""
    chain = tk.option_chain(expiry)
    return chain.calls if option_type == "call" else chain.puts


def _nearest_strike(df, target: float):
    """Return row whose strike is closest to target."""
    idx = (df["strike"] - target).abs().idxmin()
    return df.loc[idx]


# ── Endpoints ───────────────────────────────────────────────────────────────

@app.post("/fetch_atm_iv")
def fetch_atm_iv():
    body = request.get_json(silent=True) or {}
    ticker = (body.get("ticker") or "").upper().strip()
    if not ticker:
        return jsonify(error="ticker is required"), 422

    try:
        tk = yf.Ticker(ticker)
        current_price = float(tk.fast_info.last_price)

        expiry = tk.options[0]
        calls = _get_chain(tk, expiry, "call")

        row = _nearest_strike(calls, current_price)
        atm_iv = float(row["impliedVolatility"])
        atm_strike = float(row["strike"])

        return jsonify(
            ticker=ticker,
            current_price=round(current_price, 2),
            atm_strike=round(atm_strike, 2),
            atm_iv=round(atm_iv, 6),
            snapshot_date=date.today().isoformat(),
        )
    except Exception as exc:
        logger.error("fetch_atm_iv error for %s: %s", ticker, exc)
        return jsonify(error=str(exc)), 422


@app.post("/fetch_option_detail")
def fetch_option_detail():
    body = request.get_json(silent=True) or {}
    ticker = (body.get("ticker") or "").upper().strip()
    strike = body.get("strike")
    expiry_date = body.get("expiry_date")
    option_type = (body.get("option_type") or "call").lower()

    missing = [f for f, v in [("ticker", ticker), ("strike", strike), ("expiry_date", expiry_date)] if not v]
    if missing:
        return jsonify(error=f"missing fields: {', '.join(missing)}"), 422
    if option_type not in ("call", "put"):
        return jsonify(error="option_type must be 'call' or 'put'"), 422

    try:
        strike = float(strike)
        tk = yf.Ticker(ticker)
        current_price = float(tk.fast_info.last_price)

        available = tk.options
        if expiry_date not in available:
            return jsonify(error=f"expiry {expiry_date} not available; options: {available[:5]}"), 422

        df = _get_chain(tk, expiry_date, option_type)
        row = _nearest_strike(df, strike)
        matched_strike = float(row["strike"])

        iv = float(row["impliedVolatility"])

        T = years_to_expiry(expiry_date)
        delta = bs_delta(current_price, matched_strike, T, r=0.045, sigma=iv, option_type=option_type)

        return jsonify(
            ticker=ticker,
            strike=round(matched_strike, 2),
            expiry_date=expiry_date,
            option_type=option_type,
            current_price=round(current_price, 2),
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
