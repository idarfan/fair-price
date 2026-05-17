#!/usr/bin/env python3
"""
Backfill 90 days of IV skew history using yfinance historical prices.

Strategy:
  1. Download 120 days of daily OHLCV for each ticker.
  2. Compute 21-day rolling realised volatility (annualised) as ATM-IV proxy.
  3. Apply per-ticker skew multipliers to estimate 25-delta put/call IV.
  4. Compute skew_pts = (put_iv - call_iv) * 100.
  5. Upsert into skew_rank_daily; skip dates where a real row already exists.

NOTE: rows inserted here are ESTIMATES based on historical volatility.
Real IV data starts accumulating from today's snapshot onward.
"""

import math
import os
import sys
from datetime import date, timedelta

import numpy as np
import psycopg2
import yfinance as yf

# ── Skew model ──────────────────────────────────────────────────────────────
# Typical 25-delta put/call multipliers relative to ATM HV.
# Equity skew: puts costlier than calls (negative skew premium).
# SQQQ is an inverse ETF — call skew instead of put skew.
SKEW_PARAMS: dict[str, tuple[float, float]] = {
    "QQQ":  (1.12, 0.90),
    "SPY":  (1.10, 0.91),
    "IWM":  (1.13, 0.89),
    "SQQQ": (0.88, 1.18),  # Inverse ETF: call IV > put IV
    "TQQQ": (1.22, 0.84),  # 3× levered: steep put skew
    "GLD":  (1.06, 0.97),
    "TLT":  (1.09, 0.93),
}
DEFAULT_SKEW = (1.10, 0.92)

HV_WINDOW   = 21   # trading-day window for rolling HV
BACKFILL_DAYS = 100  # calendar days to fetch (gives ~90 trading days)

# ── DB connection ────────────────────────────────────────────────────────────
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_USER = os.environ.get("DB_USER", "idarfan")
DB_PASS = os.environ.get("DB_PASSWORD", "")
DB_NAME = os.environ.get("DB_NAME", "fairprice_production")


def connect():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        user=DB_USER, password=DB_PASS,
        dbname=DB_NAME,
    )


def existing_dates(cur, ticker: str) -> set[date]:
    cur.execute(
        "SELECT snapshot_date FROM skew_rank_daily WHERE ticker = %s",
        (ticker,),
    )
    return {row[0] for row in cur.fetchall()}


def fetch_hv_series(ticker: str) -> dict[date, float]:
    """Return {date: annualised_HV} for the past BACKFILL_DAYS calendar days."""
    raw = yf.download(
        ticker,
        period=f"{BACKFILL_DAYS + 30}d",
        interval="1d",
        progress=False,
        auto_adjust=True,
    )
    if raw.empty:
        return {}

    closes = raw["Close"]
    if hasattr(closes, "squeeze"):
        closes = closes.squeeze()
    closes = closes.dropna()

    log_ret = np.log(closes / closes.shift(1)).dropna()
    rolling_hv = log_ret.rolling(HV_WINDOW).std() * math.sqrt(252)

    result: dict[date, float] = {}
    cutoff = date.today() - timedelta(days=BACKFILL_DAYS)
    for dt, hv in rolling_hv.dropna().items():
        d = dt.date() if hasattr(dt, "date") else dt
        if d >= cutoff:
            result[d] = float(hv)
    return result


def compute_percentile_rank(value: float, all_values: list[float]) -> float:
    """Percentile rank of value in the list (0–100)."""
    if not all_values:
        return 50.0
    below = sum(1 for v in all_values if v < value)
    return round(below / len(all_values) * 100, 1)


def backfill_ticker(cur, ticker: str) -> int:
    put_mult, call_mult = SKEW_PARAMS.get(ticker, DEFAULT_SKEW)
    existing = existing_dates(cur, ticker)

    hv_series = fetch_hv_series(ticker)
    if not hv_series:
        print(f"  [WARN] {ticker}: no HV data from yfinance, skipping")
        return 0

    # Compute skew values for all dates first (needed for rank)
    rows: list[tuple[date, float, float, float]] = []
    for d, hv in sorted(hv_series.items()):
        if d in existing:
            continue
        if d >= date.today():
            continue
        put_iv  = round(hv * put_mult, 6)
        call_iv = round(hv * call_mult, 6)
        skew    = round((put_iv - call_iv) * 100, 4)
        rows.append((d, put_iv, call_iv, skew))

    if not rows:
        print(f"  {ticker}: all dates already present, nothing to insert")
        return 0

    # Compute skew_rank over the full HV history available
    all_skews = [r[3] for r in rows]
    inserted  = 0

    for d, put_iv, call_iv, skew in rows:
        rank = compute_percentile_rank(skew, all_skews)
        cur.execute("""
            INSERT INTO skew_rank_daily
              (ticker, snapshot_date, put_iv_025, call_iv_025, skew_pts, skew_rank, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW())
            ON CONFLICT (ticker, snapshot_date) DO NOTHING
        """, (ticker, d, put_iv, call_iv, skew, rank))
        inserted += 1

    return inserted


def main():
    print(f"IV Skew backfill — connecting to {DB_NAME} @ {DB_HOST}:{DB_PORT}")
    conn = connect()
    conn.autocommit = False
    cur  = conn.cursor()

    # Get watchlist symbols from DB
    cur.execute("SELECT DISTINCT symbol FROM iv_watchlists WHERE active = true ORDER BY symbol")
    tickers = [row[0] for row in cur.fetchall()]

    if not tickers:
        print("No active IV watchlist symbols found — run seeds first.")
        sys.exit(1)

    print(f"Backfilling {len(tickers)} tickers: {', '.join(tickers)}")
    total = 0

    for ticker in tickers:
        print(f"\n→ {ticker}")
        try:
            n = backfill_ticker(cur, ticker)
            print(f"  inserted {n} rows")
            total += n
        except Exception as exc:
            print(f"  [ERROR] {ticker}: {exc}")
            conn.rollback()
            continue

    conn.commit()
    cur.close()
    conn.close()
    print(f"\nDone — {total} rows inserted total.")


if __name__ == "__main__":
    main()
