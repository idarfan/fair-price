#!/usr/bin/env python3
"""
One-shot fix: populate iv_daily_snapshots.current_price for dates
that exist in skew_rank_daily but are missing from iv_daily_snapshots.
"""

import os
from collections import defaultdict
from datetime import date, timedelta

import psycopg2
import yfinance as yf

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_USER = os.environ.get("DB_USER", "idarfan")
DB_PASS = os.environ.get("DB_PASSWORD", "")
DB_NAME = os.environ.get("DB_NAME", "fairprice_development")


def connect():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        user=DB_USER, password=DB_PASS,
        dbname=DB_NAME,
    )


def main():
    conn = connect()
    cur  = conn.cursor()

    cur.execute("""
        SELECT s.ticker, s.snapshot_date
        FROM skew_rank_daily s
        LEFT JOIN iv_daily_snapshots d
          ON d.ticker = s.ticker AND d.snapshot_date = s.snapshot_date
        WHERE d.id IS NULL OR d.current_price IS NULL
        ORDER BY s.ticker, s.snapshot_date
    """)
    missing = cur.fetchall()

    if not missing:
        print("Nothing to fix.")
        return

    # Group by ticker
    by_ticker: dict[str, list[date]] = defaultdict(list)
    for ticker, d in missing:
        by_ticker[ticker].append(d)

    print(f"Found {len(missing)} missing price entries across {len(by_ticker)} tickers")

    total = 0
    for ticker, dates in by_ticker.items():
        earliest = min(dates)
        latest   = max(dates)
        # Add a buffer to ensure we get enough trading days
        start = (earliest - timedelta(days=5)).isoformat()
        end   = (latest   + timedelta(days=2)).isoformat()

        print(f"  {ticker}: fetching {start} → {end} ({len(dates)} dates needed)")
        raw = yf.download(ticker, start=start, end=end, interval="1d",
                          progress=False, auto_adjust=True)
        if raw.empty:
            print(f"    [WARN] no data from yfinance")
            continue

        closes = raw["Close"]
        if hasattr(closes, "squeeze"):
            closes = closes.squeeze()

        price_map: dict[date, float] = {}
        for dt, price in closes.items():
            d = dt.date() if hasattr(dt, "date") else dt
            price_map[d] = round(float(price), 2)

        inserted = 0
        for d in dates:
            price = price_map.get(d)
            if price is None:
                print(f"    [WARN] {d} not in yfinance data (holiday?)")
                continue
            cur.execute("""
                INSERT INTO iv_daily_snapshots
                  (ticker, snapshot_date, current_price, created_at, updated_at)
                VALUES (%s, %s, %s, NOW(), NOW())
                ON CONFLICT (ticker, snapshot_date) DO UPDATE
                  SET current_price = EXCLUDED.current_price,
                      updated_at    = NOW()
            """, (ticker, d, price))
            inserted += 1

        print(f"    → {inserted} rows upserted")
        total += inserted

    conn.commit()
    cur.close()
    conn.close()
    print(f"\nDone — {total} prices inserted/updated.")


if __name__ == "__main__":
    main()
