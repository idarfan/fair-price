#!/usr/bin/env python3
"""
Options Price Tracker — Daily EOD Snapshot Collector
====================================================
Fetches current options chain data from Yahoo Finance via yfinance,
filters by DTE/strike range/OI, and upserts into PostgreSQL.

Designed to share the same PostgreSQL database as a Rails app.

Usage:
    python3 scripts/options_collector.py                  # collect all active tickers
    python3 scripts/options_collector.py --symbols NOK AMD # collect specific tickers
    python3 scripts/options_collector.py --dry-run         # preview without writing

Environment:
    DATABASE_URL — PostgreSQL connection string
                   (e.g. postgresql://user:pass@localhost:5432/fairprice_development)

Schedule (crontab, Taiwan time):
    0 6 * * 2-7 cd /path/to/project && python3 scripts/options_collector.py
"""

import os
import sys
import json
import time
import logging
import argparse
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

import yfinance as yf
import psycopg2
from psycopg2.extras import execute_values

# Load .env from project root (same directory logic as database.yml lookup)
def _load_dotenv():
    env_path = Path(__file__).parent.parent / ".env"
    if not env_path.exists():
        return
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            os.environ.setdefault(key, val)

_load_dotenv()

# ── Logging ──────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("options_collector")

# ── Config defaults ──────────────────────────────────────────────────
DEFAULT_MIN_DTE = 7
DEFAULT_MAX_DTE = 90
DEFAULT_STRIKE_RANGE = 0.30  # ±30% of underlying price
DEFAULT_MIN_OI = 0
INTER_TICKER_DELAY = 2  # seconds between tickers to avoid rate limiting


def get_db_url() -> str:
    """Resolve DATABASE_URL from env or Rails-style database.yml."""
    url = os.environ.get("DATABASE_URL")
    if url:
        return url

    # Try reading from Rails config
    yml_path = os.path.join(os.path.dirname(__file__), "..", "config", "database.yml")
    if os.path.exists(yml_path):
        try:
            import yaml
            with open(yml_path) as f:
                config = yaml.safe_load(f)
            env = os.environ.get("RAILS_ENV", "development")
            db = config.get(env, {})
            host = db.get("host", "localhost")
            port = db.get("port", 5432)
            user = db.get("username", "")
            pw = db.get("password", "")
            name = db.get("database", "")
            return f"postgresql://{user}:{pw}@{host}:{port}/{name}"
        except Exception as e:
            log.warning(f"Could not parse database.yml: {e}")

    log.error("DATABASE_URL not set and database.yml not found")
    sys.exit(1)


def connect_db(url: str):
    """Connect to PostgreSQL."""
    conn = psycopg2.connect(url)
    conn.autocommit = False
    return conn


def get_tracked_tickers(conn, symbols: list[str] | None = None) -> list[dict]:
    """Fetch active tracked tickers from DB."""
    cur = conn.cursor()
    if symbols:
        placeholders = ",".join(["%s"] * len(symbols))
        cur.execute(
            f"SELECT id, symbol, config FROM tracked_tickers WHERE symbol IN ({placeholders}) AND active = true",
            [s.upper() for s in symbols],
        )
    else:
        cur.execute("SELECT id, symbol, config FROM tracked_tickers WHERE active = true")

    rows = cur.fetchall()
    cur.close()

    tickers = []
    for row in rows:
        config = row[2] if isinstance(row[2], dict) else json.loads(row[2] or "{}")
        tickers.append({"id": row[0], "symbol": row[1], "config": config})
    return tickers


def fetch_options_chain(symbol: str, config: dict) -> list[dict]:
    """
    Fetch options chain from Yahoo Finance for a single ticker.
    Returns a list of snapshot dicts ready for DB insertion.
    """
    min_dte = config.get("min_dte", DEFAULT_MIN_DTE)
    max_dte = config.get("max_dte", DEFAULT_MAX_DTE)
    strike_range = config.get("strike_range", DEFAULT_STRIKE_RANGE)
    min_oi = config.get("min_oi", DEFAULT_MIN_OI)

    tk = yf.Ticker(symbol)

    # Get current underlying price
    info = tk.info or {}
    underlying_price = info.get("regularMarketPrice") or info.get("currentPrice")
    if not underlying_price:
        hist = tk.history(period="1d")
        if hist.empty:
            log.warning(f"{symbol}: Cannot determine underlying price, skipping")
            return []
        underlying_price = float(hist["Close"].iloc[-1])

    underlying_price = float(underlying_price)
    log.info(f"{symbol}: underlying price = ${underlying_price:.2f}")

    # Get available expirations
    try:
        expirations = tk.options
    except Exception as e:
        log.warning(f"{symbol}: Cannot get expirations: {e}")
        return []

    if not expirations:
        log.warning(f"{symbol}: No options available")
        return []

    today = date.today()
    snapshots = []

    for exp_str in expirations:
        exp_date = datetime.strptime(exp_str, "%Y-%m-%d").date()
        dte = (exp_date - today).days

        # Filter by DTE range
        if dte < min_dte or dte > max_dte:
            continue

        try:
            chain = tk.option_chain(exp_str)
        except Exception as e:
            log.warning(f"{symbol} {exp_str}: Error fetching chain: {e}")
            continue

        for opt_type, df in [("call", chain.calls), ("put", chain.puts)]:
            if df.empty:
                continue

            for _, row in df.iterrows():
                strike = float(row.get("strike", 0))

                # Filter by strike range
                if strike < underlying_price * (1 - strike_range):
                    continue
                if strike > underlying_price * (1 + strike_range):
                    continue

                # Filter by open interest
                oi = int(row.get("openInterest", 0) or 0)
                if oi < min_oi:
                    continue

                snapshots.append({
                    "snapshot_date": today,
                    "snapped_at": datetime.now(timezone.utc),
                    "contract_symbol": str(row.get("contractSymbol", "")),
                    "option_type": opt_type,
                    "expiration": exp_date,
                    "strike": strike,
                    "last_price": _safe_float(row.get("lastPrice")),
                    "bid": _safe_float(row.get("bid")),
                    "ask": _safe_float(row.get("ask")),
                    "volume": _safe_int(row.get("volume")),
                    "open_interest": oi,
                    "implied_volatility": _safe_float(row.get("impliedVolatility")),
                    "in_the_money": bool(row.get("inTheMoney", False)),
                    "underlying_price": underlying_price,
                })

    log.info(f"{symbol}: collected {len(snapshots)} contracts across {len(expirations)} expirations")
    return snapshots


def upsert_snapshots(conn, ticker_id: int, snapshots: list[dict]):
    """
    Bulk upsert snapshots into option_snapshots table.
    Uses ON CONFLICT to avoid duplicates on same day re-runs.
    """
    if not snapshots:
        return 0

    cur = conn.cursor()

    sql = """
        INSERT INTO option_snapshots (
            tracked_ticker_id, snapshot_date, snapped_at, contract_symbol, option_type,
            expiration, strike, last_price, bid, ask, volume,
            open_interest, implied_volatility, in_the_money, underlying_price,
            created_at, updated_at
        ) VALUES %s
        ON CONFLICT (tracked_ticker_id, date_trunc('hour', snapped_at), contract_symbol)
        DO UPDATE SET
            last_price = EXCLUDED.last_price,
            bid = EXCLUDED.bid,
            ask = EXCLUDED.ask,
            volume = EXCLUDED.volume,
            open_interest = EXCLUDED.open_interest,
            implied_volatility = EXCLUDED.implied_volatility,
            in_the_money = EXCLUDED.in_the_money,
            underlying_price = EXCLUDED.underlying_price,
            snapped_at = EXCLUDED.snapped_at,
            updated_at = EXCLUDED.updated_at
    """

    now = datetime.now(timezone.utc)
    values = [
        (
            ticker_id,
            s["snapshot_date"],
            s["snapped_at"],
            s["contract_symbol"],
            s["option_type"],
            s["expiration"],
            s["strike"],
            s["last_price"],
            s["bid"],
            s["ask"],
            s["volume"],
            s["open_interest"],
            s["implied_volatility"],
            s["in_the_money"],
            s["underlying_price"],
            now,
            now,
        )
        for s in snapshots
    ]

    execute_values(cur, sql, values, page_size=500)
    count = cur.rowcount
    conn.commit()
    cur.close()
    return count


def _safe_float(val):
    """Convert to float, returning None for NaN/None."""
    if val is None:
        return None
    try:
        f = float(val)
        if f != f:  # NaN check
            return None
        return f
    except (ValueError, TypeError):
        return None


def _safe_int(val):
    """Convert to int, returning 0 for None/NaN."""
    if val is None:
        return 0
    try:
        f = float(val)
        if f != f:
            return 0
        return int(f)
    except (ValueError, TypeError):
        return 0


def main():
    parser = argparse.ArgumentParser(description="Options Price Tracker — Daily Collector")
    parser.add_argument("--symbols", nargs="+", help="Specific ticker symbols (overrides DB)")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and display without writing to DB")
    parser.add_argument("--add", nargs="+", help="Add ticker(s) to tracked_tickers and exit")
    parser.add_argument("--list", action="store_true", help="List all tracked tickers and exit")
    parser.add_argument("--min-dte", type=int, default=None, help="Override min DTE filter")
    parser.add_argument("--max-dte", type=int, default=None, help="Override max DTE filter")
    args = parser.parse_args()

    db_url = get_db_url()
    conn = connect_db(db_url)
    log.info("Connected to database")

    # ── --list: show tracked tickers ──
    if args.list:
        tickers = get_tracked_tickers(conn)
        if not tickers:
            print("No tracked tickers found. Use --add SYMBOL to add one.")
        else:
            print(f"\n{'Symbol':<10} {'Active':<8} {'Config'}")
            print("-" * 50)
            for t in tickers:
                print(f"{t['symbol']:<10} {'yes':<8} {json.dumps(t['config'])}")
        conn.close()
        return

    # ── --add: insert new tickers ──
    if args.add:
        cur = conn.cursor()
        now = datetime.utcnow()
        for sym in args.add:
            sym_upper = sym.upper()
            try:
                cur.execute(
                    """INSERT INTO tracked_tickers (symbol, active, config, created_at, updated_at)
                       VALUES (%s, true, %s, %s, %s)
                       ON CONFLICT (symbol) DO UPDATE SET active = true, updated_at = %s""",
                    (sym_upper, json.dumps({}), now, now, now),
                )
                log.info(f"Added/activated: {sym_upper}")
            except Exception as e:
                log.error(f"Error adding {sym_upper}: {e}")
        conn.commit()
        cur.close()
        conn.close()
        return

    # ── Main collection ──
    tickers = get_tracked_tickers(conn, args.symbols)
    if not tickers:
        log.warning("No tracked tickers found. Use --add SYMBOL to add tickers first.")
        conn.close()
        return

    log.info(f"Collecting options for {len(tickers)} ticker(s): {[t['symbol'] for t in tickers]}")

    total_inserted = 0
    for i, ticker in enumerate(tickers):
        config = ticker["config"].copy()

        # Apply CLI overrides
        if args.min_dte is not None:
            config["min_dte"] = args.min_dte
        if args.max_dte is not None:
            config["max_dte"] = args.max_dte

        try:
            snapshots = fetch_options_chain(ticker["symbol"], config)

            if args.dry_run:
                log.info(f"[DRY RUN] {ticker['symbol']}: {len(snapshots)} contracts")
                if snapshots:
                    # Show sample
                    sample = snapshots[0]
                    log.info(f"  Sample: {sample['contract_symbol']} "
                             f"strike={sample['strike']} "
                             f"bid={sample['bid']} ask={sample['ask']} "
                             f"iv={sample['implied_volatility']}")
            else:
                count = upsert_snapshots(conn, ticker["id"], snapshots)
                total_inserted += count
                log.info(f"{ticker['symbol']}: upserted {count} rows")

        except Exception as e:
            log.error(f"{ticker['symbol']}: Error — {e}")
            conn.rollback()

        # Rate limit between tickers
        if i < len(tickers) - 1:
            time.sleep(INTER_TICKER_DELAY)

    if not args.dry_run:
        log.info(f"Done. Total rows upserted: {total_inserted}")

    conn.close()


if __name__ == "__main__":
    main()
