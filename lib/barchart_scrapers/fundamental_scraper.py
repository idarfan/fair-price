"""
Barchart Overview (Fundamentals) scraper (CDP direct WebSocket — no Playwright)
Output: JSON to stdout
Usage: python3 fundamental_scraper.py MU
"""
import asyncio
import json
import re
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval


TARGET_PATH = "overview"


def clean_num(s):
    if not s:
        return None
    cleaned = re.sub(r"[+,%$]", "", s.replace(",", "")).strip()
    if cleaned.endswith("M"):
        try:
            return float(cleaned[:-1])
        except ValueError:
            return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def clean_bigint(s):
    if not s:
        return None
    cleaned = re.sub(r"[+,$]", "", s.replace(",", "")).strip()
    try:
        return int(float(cleaned))
    except ValueError:
        return None


def parse_date(s):
    if not s:
        return None
    m = re.search(r"(\d{2}/\d{2}/\d{2,4})", s)
    if not m:
        return None
    parts = m.group(1).split("/")
    month, day, year = parts
    if len(year) == 2:
        year = "20" + year
    return f"{year}-{month}-{day}"


EXTRACT_JS = """
(() => {
    // Fundamentals block (not the cot-table-wrapper)
    let fundText = '';
    for (const el of document.querySelectorAll('div.barchart-content-block.symbol-fundamentals')) {
        if (!el.classList.contains('bc-cot-table-wrapper')) {
            fundText = el.innerText || '';
            break;
        }
    }
    // Options overview
    const optEl = document.querySelector('div.barchart-content-block.symbol-fundamentals.bc-cot-table-wrapper');
    const optText = optEl ? (optEl.innerText || '') : '';
    // Analyst rating
    const analystEl = document.querySelector('div.bc-analyst-rating-pie');
    const analystText = analystEl ? (analystEl.innerText || '') : '';
    // Earnings date span
    const earningsEl = document.querySelector('span.right.earnings-background');
    const earningsSpan = earningsEl ? (earningsEl.innerText || '').trim() : '';
    // Earnings estimates block (bc-rating-and-estimates)
    const estimatesEl = document.querySelector('div.barchart-content-block.bc-rating-and-estimates');
    const estimatesText = estimatesEl ? (estimatesEl.innerText || '') : '';
    // Session check
    const sessionOk = !!document.querySelector('div.barchart-content-block.symbol-fundamentals');
    return { fundText, optText, analystText, earningsSpan, estimatesText, sessionOk };
})()
"""


async def main(symbol):
    _, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=6000)
    if not ws:
        print(json.dumps({"status": "error", "error": "No Chrome CDP page found"}))
        return

    raw = await cdp_eval(ws, EXTRACT_JS)

    if not raw or not raw.get("sessionOk"):
        print(json.dumps({"status": "barchart_session_expired"}))
        return

    data = {}

    # === Fundamentals block ===
    SKIP = {"Fundamentals", "See More", "SECTOR", "INDUSTRY GROUPING:", "Indices S&P 100",
            "Computers and Technology"}
    lines = [l.strip() for l in raw["fundText"].splitlines() if l.strip() and l.strip() not in SKIP]

    FIELD_MAP = {
        "Market Capitalization, $K":      ("market_cap_k",          clean_bigint),
        "Shares Outstanding, K":          ("shares_outstanding_k",  clean_bigint),
        "Annual Sales, $":                ("annual_revenue_m",      clean_num),
        "Annual Income, $":               ("annual_income_m",       clean_num),
        "EBIT $":                         ("ebit_m",                clean_num),
        "EBITDA $":                       ("ebitda_m",              clean_num),
        "60-Month Beta":                  ("beta_60m",              clean_num),
        "Price/Earnings ttm":             ("pe_ttm",                clean_num),
        "Price/Sales":                    ("ps_ratio",              clean_num),
        "Price/Book":                     ("pb_ratio",              clean_num),
        "Price/Cash Flow":                ("pcf_ratio",             clean_num),
        "Earnings Per Share ttm":         ("eps_ttm",               clean_num),
        "Annual Dividend & Yield (Fwd)":  ("dividend_annual",       lambda s: clean_num(s.split()[0]) if s else None),
    }

    i = 0
    while i < len(lines) - 1:
        label, value = lines[i], lines[i + 1]
        if label in FIELD_MAP:
            col, fn = FIELD_MAP[label]
            data[col] = fn(value)
            i += 2
        elif label == "Most Recent Earnings":
            m = re.search(r"\$?([\d.]+)", value)
            data["most_recent_eps"] = float(m.group(1)) if m else None
            data["most_recent_earnings_date"] = parse_date(value)
            i += 2
        elif label == "Sector":
            data["sector"] = value
            i += 2
        else:
            i += 1

    # === Earnings date (authoritative) ===
    es = raw.get("earningsSpan", "")
    if es:
        data["next_earnings_date"] = parse_date(es)
        m = re.search(r"\[(AMC|BMO|MKT)\]", es)
        data["earnings_time"] = m.group(1) if m else None

    # === Options overview ===
    OPT_MAP = {
        "Implied Volatility":    ("iv",                 lambda s: clean_num(s.split()[0])),
        "Historical Volatility": ("hist_vol",           clean_num),
        "IV Percentile":         ("iv_percentile",      lambda s: int(clean_num(s)) if clean_num(s) is not None else None),
        "IV Rank":               ("iv_rank",            clean_num),
        "Expected Move (DTE 5)": ("expected_move_pct",  lambda s: clean_num(s.split("(")[-1].rstrip(")")) if "(" in (s or "") else clean_num(s)),
        "Put/Call Vol Ratio":    ("put_call_vol_ratio", clean_num),
        "Today's Volume":        ("options_volume",     clean_bigint),
        "Volume Avg (30-Day)":   ("options_avg_volume", clean_bigint),
        "Put/Call OI Ratio":     ("put_call_oi_ratio",  clean_num),
        "Today's Open Interest": ("open_interest",      clean_bigint),
    }
    opt_lines = [l.strip() for l in raw["optText"].splitlines() if l.strip()]
    j = 0
    while j < len(opt_lines) - 1:
        label, value = opt_lines[j], opt_lines[j + 1]
        if label in OPT_MAP:
            col, fn = OPT_MAP[label]
            data[col] = fn(value)
            j += 2
        else:
            j += 1

    # === Analyst rating ===
    at = raw.get("analystText", "")
    if at:
        for pat, key in [
            (r"(\d+)\s+Strong Buy",    "analyst_strong_buy"),
            (r"(\d+)\s+Moderate Buy",  "analyst_moderate_buy"),
            (r"(\d+)\s+Hold",          "analyst_hold"),
            (r"(\d+)\s+(?:Moderate |Strong )?Sell", "analyst_sell"),
        ]:
            m = re.search(pat, at)
            data[key] = int(m.group(1)) if m else 0

    # === Earnings Estimates (current quarter) ===
    est_text = raw.get("estimatesText", "")
    if est_text:
        m = re.search(r"Average Estimate[\s\S]{0,10}?\$?([\d.]+)", est_text)
        data["eps_estimate_current_qtr"] = float(m.group(1)) if m else None

        m = re.search(r"Prior Year[\s\S]{0,10}?\$?([-\d.]+)", est_text)
        data["eps_prior_year_estimate"] = float(m.group(1)) if m else None

        m = re.search(r"Growth Rate Est\.[^\n]*\n?\s*([+-]?[\d,]+\.?\d*)%", est_text)
        if m:
            data["eps_growth_est_yoy"] = float(m.group(1).replace(",", ""))
        else:
            data["eps_growth_est_yoy"] = None

    data["status"] = "success"
    print(json.dumps(data))

if __name__ == "__main__":
    symbol = sys.argv[1].upper() if len(sys.argv) > 1 else "MU"
    asyncio.run(main(symbol))
