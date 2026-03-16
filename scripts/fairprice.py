#!/usr/bin/env python3
"""
FairPrice — US Stock Fair Value Calculator
Usage: python3 fairprice.py TICKER
       python3 fairprice.py TICKER --input 5000 --output 1200
"""

import json, os, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import urlopen, Request

try:
    import yfinance as yf
except ImportError:
    sys.exit("❌ 需要 yfinance：pip install yfinance --break-system-packages")

try:
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

# ── 常數 ──────────────────────────────────────────────────────────
DISCOUNT_RATE   = 0.10
TERMINAL_GROWTH = 0.03
FORECAST_YEARS  = 5
_CACHE = "/tmp/.usd_twd_cache"
_FX_CACHE = "/tmp/.fx_cache"      # 通用 FX 快取
_TTL   = 3600
_URLS  = [
    "https://open.er-api.com/v6/latest/USD",
    "https://api.exchangerate-api.com/v4/latest/USD",
]

# 常見外幣對 USD 的 fallback 匯率（僅在 API 失敗時使用）
_FX_FALLBACK = {"JPY": 150.0, "GBP": 0.79, "EUR": 0.92, "KRW": 1350.0,
                "CNY": 7.25, "HKD": 7.80, "TWD": 32.50, "CAD": 1.36,
                "AUD": 1.55, "CHF": 0.88, "INR": 83.0, "BRL": 5.0}

INDUSTRY_PE      = {"Technology": 35, "Communication Services": 28, "Consumer Cyclical": 20, "Consumer Defensive": 22, "Healthcare": 22, "Financial Services": 15, "Industrials": 20, "Basic Materials": 14, "Energy": 12, "Utilities": 18, "Real Estate": 18, "default": 25}
INDUSTRY_PB      = {"Financial Services": 1.5, "Real Estate": 1.2, "Utilities": 1.8, "Technology": 8.0, "Healthcare": 4.0, "default": 2.0}
SECTOR_EV_EBITDA = {"Energy": 8, "Basic Materials": 10, "Industrials": 14, "default": 12}

# ── Claude API 定價（USD / 百萬 token）──────────────────────────
# 來源：https://platform.claude.com/docs/en/about-claude/pricing
# 格式：model_keyword → (input_per_mtok, output_per_mtok)
# 匹配邏輯：取模型名稱中最長匹配的 key
MODEL_PRICING = {
    # Opus 系列
    "opus-4-6":    (5.00,  25.00),
    "opus-4-5":    (5.00,  25.00),
    "opus-4.5":    (5.00,  25.00),   # 相容寫法
    "opus-4-1":    (15.00, 75.00),
    "opus-4.1":    (15.00, 75.00),
    "opus-4-0":    (15.00, 75.00),
    # Sonnet 系列
    "sonnet-4-5":  (3.00,  15.00),
    "sonnet-4.5":  (3.00,  15.00),
    "sonnet-4-0":  (3.00,  15.00),
    "sonnet-4":    (3.00,  15.00),
    "sonnet-3-7":  (3.00,  15.00),
    "sonnet-3.7":  (3.00,  15.00),
    "sonnet-3-5":  (3.00,  15.00),
    "sonnet-3.5":  (3.00,  15.00),
    # Haiku 系列
    "haiku-4-5":   (1.00,   5.00),
    "haiku-4.5":   (1.00,   5.00),
    "haiku-3-5":   (0.80,   4.00),
    "haiku-3.5":   (0.80,   4.00),
    "haiku-3":     (0.25,   1.25),
}

def _get_pricing(model_name):
    """根據模型名稱回傳 (input_price, output_price) per million tokens。
       使用最長匹配，避免 'haiku-3' 誤匹配 'haiku-3-5'。"""
    m = (model_name or "").lower().replace("/", "-")
    best_key, best_len = None, 0
    for key in MODEL_PRICING:
        if key in m and len(key) > best_len:
            best_key, best_len = key, len(key)
    if best_key:
        return MODEL_PRICING[best_key]
    # fallback：按家族粗略匹配
    if "opus" in m:   return (5.00, 25.00)
    if "haiku" in m:  return (1.00, 5.00)
    return (3.00, 15.00)  # 預設 Sonnet

# ── 讀取模型 ──────────────────────────────────────────────────────
def get_model():
    """取得目前使用的模型：
       1. 環境變數 OPENCLAW_MODEL（agent 可在執行時注入）
       2. agents.defaults.model.large（Skill 通常用 large）
       3. agents.defaults.model.primary
       4. fallback
    """
    env_model = os.environ.get("OPENCLAW_MODEL")
    if env_model:
        return env_model
    config_path = os.path.expanduser("~/.openclaw/openclaw.json")
    try:
        with open(config_path) as f:
            config = json.load(f)
            models = config.get("agents", {}).get("defaults", {}).get("model", {})
            return models.get("large") or models.get("primary") or "claude-sonnet-4-5"
    except Exception:
        pass
    return "claude-sonnet-4-5"  # fallback

# ── 計費模式偵測 ──────────────────────────────────────────────────
def _has_pro_profile_in_config() -> bool:
    """config 裡是否有 token 模式的 PRO profile"""
    config_path = os.path.expanduser("~/.openclaw/openclaw.json")
    try:
        with open(config_path) as f:
            config = json.load(f)
        profiles = config.get("auth", {}).get("profiles", {})
        return any(p.get("mode") == "token" for p in profiles.values())
    except Exception:
        return False

def detect_billing_mode() -> str:
    """判斷目前的計費模式，優先讀 gateway log（runtime 實際狀態）。

    回傳：
      "pro"      → 使用 Claude PRO 訂閱（token mode）
      "fallback" → PRO 訂閱超量，已改用 Claude API Token 計費
      "api"      → 純 Claude API Token 計費
    """
    from datetime import datetime, timezone

    today    = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    log_path = f"/tmp/openclaw/openclaw-{today}.log"
    last_mode = None

    try:
        with open(log_path) as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    entry = json.loads(raw)
                except Exception:
                    continue
                msg = str(entry.get("0", ""))
                if msg.startswith("Auth profile:"):
                    if "token" in msg:
                        last_mode = "token"
                    elif "api_key" in msg:
                        last_mode = "api_key"
    except FileNotFoundError:
        pass
    except Exception:
        pass

    if last_mode == "token":
        return "pro"
    elif last_mode == "api_key":
        return "fallback" if _has_pro_profile_in_config() else "api"
    else:
        # log 無資料，退回 config 判斷
        config_path = os.path.expanduser("~/.openclaw/openclaw.json")
        try:
            with open(config_path) as f:
                config = json.load(f)
            auth     = config.get("auth", {})
            order    = auth.get("order", {}).get("anthropic", [])
            profiles = auth.get("profiles", {})
            modes    = [profiles.get(k, {}).get("mode", "api_key") for k in order]
            first    = modes[0] if modes else "api_key"
            if first == "token":
                return "pro"
            elif first == "api_key" and "token" in modes:
                return "fallback"
        except Exception:
            pass
        return "api"

# ── 生成股價區間圖表 ─────────────────────────────────────────────
def generate_price_chart_png(ticker, current_price, high_52w, low_52w):
    """生成 PNG 圖表（52W 高低點 + 當前價格）"""
    if not HAS_MATPLOTLIB:
        return None
    
    try:
        range_span = high_52w - low_52w
        if range_span == 0:
            range_span = 1
        
        current_pct = ((current_price - low_52w) / range_span) * 100
        current_pct = max(0, min(100, current_pct))
        
        # 建立圖表
        fig, ax = plt.subplots(figsize=(10, 3), dpi=100)
        fig.patch.set_facecolor('white')
        ax.set_facecolor('white')
        
        # 隱藏軸
        ax.set_xlim(0, 100)
        ax.set_ylim(0, 2)
        ax.axis('off')
        
        # 背景條
        bg_rect = mpatches.Rectangle((5, 0.8), 90, 0.4, linewidth=0, 
                                     facecolor='#e0e0e0', zorder=1)
        ax.add_patch(bg_rect)
        
        # 填充條（綠色）
        fill_width = (current_pct / 100) * 90
        fill_rect = mpatches.Rectangle((5, 0.8), fill_width, 0.4, linewidth=0,
                                      facecolor='#20c997', zorder=2)
        ax.add_patch(fill_rect)
        
        # 當前價格三角
        triangle_x = 5 + fill_width
        triangle = mpatches.Polygon(
            [[triangle_x, 1.3], [triangle_x - 0.5, 1.5], [triangle_x + 0.5, 1.5]],
            facecolor='#000000', zorder=3
        )
        ax.add_patch(triangle)
        
        # 標籤
        ax.text(2, 0.8, f'${low_52w:.2f}', ha='right', va='center', fontsize=10, color='#666')
        ax.text(98, 0.8, f'${high_52w:.2f}', ha='left', va='center', fontsize=10, color='#666')
        ax.text(triangle_x, 0.3, f'${current_price:.2f}', ha='center', va='top', fontsize=10, fontweight='bold')
        
        # 標題
        ax.text(50, 1.9, f'{ticker} 52WK RANGE', ha='center', fontsize=14, fontweight='bold')
        
        # 保存 PNG
        chart_dir = os.path.expanduser("~/.openclaw/workspace/stock_charts")
        os.makedirs(chart_dir, exist_ok=True)
        png_filename = f"stock_chart_{ticker}.png"
        full_path = os.path.join(chart_dir, png_filename)
        plt.savefig(full_path, format='png', bbox_inches='tight', facecolor='white', dpi=100)
        plt.close(fig)
        
        return f"stock_charts/{png_filename}"
    except Exception as e:
        return None

# ── 匯率 ──────────────────────────────────────────────────────────
def _fetch_usd_rates():
    """取得所有 USD 匯率（帶快取），回傳 dict {currency: rate}"""
    if os.path.exists(_FX_CACHE) and time.time() - os.path.getmtime(_FX_CACHE) < _TTL:
        try: return json.loads(open(_FX_CACHE).read()), "快取"
        except Exception: pass
    def _try(url):
        with urlopen(Request(url, headers={"User-Agent": "fairprice/1.0"}), timeout=4) as r:
            d = json.loads(r.read())
        return d.get("rates") or d.get("conversion_rates", {})
    with ThreadPoolExecutor(max_workers=2) as ex:
        for f in as_completed({ex.submit(_try, u): u for u in _URLS}):
            try:
                rates = f.result()
                open(_FX_CACHE, "w").write(json.dumps(rates))
                return rates, "即時"
            except Exception: continue
    return {}, "失敗"

def get_usd_twd():
    rates, src = _fetch_usd_rates()
    if "TWD" in rates:
        return float(rates["TWD"]), src
    return 32.50, "預設"

def get_fx_rate(from_currency, to_currency="USD"):
    """取得 from_currency → to_currency 的匯率。
       例：get_fx_rate("JPY", "USD") → 0.00667（1 JPY = 0.00667 USD）"""
    if not from_currency or not to_currency:
        return 1.0
    from_currency = from_currency.upper()
    to_currency = to_currency.upper()
    if from_currency == to_currency:
        return 1.0

    rates, _ = _fetch_usd_rates()

    # 兩者都有 vs USD 的匯率時可以交叉計算
    from_per_usd = rates.get(from_currency) or _FX_FALLBACK.get(from_currency)
    to_per_usd   = rates.get(to_currency)   or (1.0 if to_currency == "USD" else _FX_FALLBACK.get(to_currency))

    if from_per_usd and to_per_usd:
        return to_per_usd / from_per_usd   # from → USD → to

    return 1.0  # 無法轉換，保持原樣

# ── 工具 ──────────────────────────────────────────────────────────
def safe(v, d=None):
    if v is None: return d
    try:
        f = float(v); return d if f != f else f
    except: return d

def per_share(total, shares):
    """FIX: 避免 or 0 把 None 變成 0.0"""
    v = safe(total)
    return v / shares if (v is not None and shares) else None

def classify(info):
    sector   = info.get("sector", "") or ""
    industry = (info.get("industry", "") or "").lower()
    eps      = safe(info.get("trailingEps"))
    if sector == "Real Estate":        return "REITs"
    if sector == "Utilities":          return "公用事業"
    if sector == "Financial Services": return "金融股"
    if sector in ("Energy", "Basic Materials") or any(
        k in industry for k in ("steel","mining","chemical","oil","gas","copper","coal")):
        return "週期股"
    if eps is not None and eps < 0:    return "虧損成長股"
    return "一般股"

# ── 估值方法 ──────────────────────────────────────────────────────
def dcf(fcf, g, r=DISCOUNT_RATE, gt=TERMINAL_GROWTH, yrs=FORECAST_YEARS):
    if not fcf or fcf <= 0: return None
    cf, pv = fcf, 0.0
    for n in range(1, yrs + 1):
        cf *= (1 + g); pv += cf / (1 + r) ** n
    return pv + cf * (1 + gt) / ((r - gt) * (1 + r) ** yrs)

def pe_val(eps, sector):
    if not eps or eps <= 0: return None
    pe = INDUSTRY_PE.get(sector, INDUSTRY_PE["default"])
    return eps * pe, pe

def peg_val(price, eps, g_pct, sector):
    """PEG 估值：回傳 (PEG=1 公允價, 當前 PEG) 或 None。
       公式：PEG = (P/E) ÷ g%  → 當 PEG=1 時，公允 P/E = g%。"""
    if not eps or eps <= 0 or not g_pct or g_pct <= 0: return None
    current_pe  = price / eps if price and price > 0 else None
    current_peg = current_pe / g_pct if current_pe else None
    fair_price  = eps * g_pct       # PEG=1 公允價
    return fair_price, current_peg

def ddm(div, g, r=0.08):
    return div * (1 + g) / (r - g) if div and div > 0 and r > g else None

def pb_val(bvps, sector):
    if not bvps or bvps <= 0: return None
    pb = INDUSTRY_PB.get(sector, INDUSTRY_PB["default"])
    return bvps * pb, pb

def excess_returns(bvps, roe, coe=0.10, g=0.03):
    if not bvps or not roe or coe <= g: return None
    return bvps + (roe - coe) * bvps / (coe - g)

def ev_ebitda_val(ebitda, net_debt, shares, sector):
    if not ebitda or ebitda <= 0 or not shares or shares <= 0: return None
    mult   = SECTOR_EV_EBITDA.get(sector, SECTOR_EV_EBITDA["default"])
    equity = ebitda * mult - (net_debt or 0)
    return (equity / shares, mult) if equity > 0 else None

def judge(price, lo, hi):
    if None in (price, lo, hi): return "⚪ 無法判斷"
    if price > hi * 1.20: return "🔴 明顯高估"
    if price > hi:        return "🟡 略微高估"
    if price < lo * 0.80: return "🟢 明顯低估（潛在買點）"
    if price < lo:        return "🟡 略微低估"
    return "🟢 合理"

# ── 主流程 ────────────────────────────────────────────────────────
def run(ticker_str, input_tokens=0, output_tokens=0, detail=True, model_override=None):
    ticker_str = ticker_str.upper()
    info = yf.Ticker(ticker_str).info
    if not info or not info.get("symbol"):
        sys.exit(f"❌ 找不到：{ticker_str}")

    name    = info.get("longName") or info.get("shortName") or ticker_str
    sector  = info.get("sector") or "Unknown"
    exchange = info.get("exchange") or info.get("exchangeName") or ""
    price   = safe(info.get("currentPrice") or info.get("regularMarketPrice"))
    shares  = safe(info.get("sharesOutstanding"))
    eps_ttm = safe(info.get("trailingEps"))
    fwd_eps = safe(info.get("forwardEps"))
    bvps    = safe(info.get("bookValue"))
    roe     = safe(info.get("returnOnEquity"))
    div     = safe(info.get("dividendRate"))

    # ── 幣別修正：ADR / 外國股票的財報幣別可能與交易幣別不同 ──
    trade_ccy = (info.get("currency") or "USD").upper()
    fin_ccy   = (info.get("financialCurrency") or trade_ccy).upper()
    fx = get_fx_rate(fin_ccy, trade_ccy) if fin_ccy != trade_ccy else 1.0
    ccy_note = ""
    if fx != 1.0:
        ccy_note = f"⚠️ 財報幣別 {fin_ccy} → 交易幣別 {trade_ccy}（匯率 {1/fx:.2f}）"

    # 聚合數據（freeCashflow, totalRevenue, ebitda, totalDebt, totalCash）
    # 在 financialCurrency 中，需要乘以 fx 轉換為交易幣別
    raw_fcf   = safe(info.get("freeCashflow"))
    raw_rev   = safe(info.get("totalRevenue"))
    raw_ebitda= safe(info.get("ebitda"))
    raw_debt  = safe(info.get("totalDebt"), 0) or 0
    raw_cash  = safe(info.get("totalCash"), 0) or 0

    ebitda   = raw_ebitda * fx if raw_ebitda else None
    fcf_ps   = per_share(raw_fcf * fx if raw_fcf else None, shares)
    rev_ps   = per_share(raw_rev * fx if raw_rev else None, shares)
    net_debt = (raw_debt - raw_cash) * fx

    # ── 成長率估算：多來源取中位數 ────────────────────────────────
    g_sources = []
    eg = safe(info.get("earningsGrowth"))
    if eg is not None and -0.5 < eg < 2.0:
        g_sources.append(("盈餘成長(YoY)", eg))
    rg = safe(info.get("revenueGrowth"))
    if rg is not None and -0.5 < rg < 2.0:
        g_sources.append(("營收成長", rg))
    if fwd_eps and eps_ttm and eps_ttm > 0:
        fg = (fwd_eps - eps_ttm) / eps_ttm
        if -0.5 < fg < 2.0:
            g_sources.append(("FwdEPS推算", fg))
    eqg = safe(info.get("earningsQuarterlyGrowth"))
    if eqg is not None and -0.5 < eqg < 2.0:
        g_sources.append(("季度盈餘成長", eqg))

    if g_sources:
        g_vals = sorted([s[1] for s in g_sources])
        g5 = g_vals[len(g_vals) // 2]   # 取中位數
    else:
        g5 = 0.10
    g5 = min(max(g5, 0.03), 0.45)
    g_detail = ", ".join(f"{n}={v*100:.1f}%" for n, v in g_sources) if g_sources else "無數據，使用預設10%"

    # ── FCF 合理性檢查 ────────────────────────────────────────────
    fcf_note = ""
    if fcf_ps and eps_ttm and eps_ttm > 0:
        fcf_ratio = fcf_ps / eps_ttm
        if fcf_ratio < 0.30:
            fcf_note = f"⚠️ FCF/EPS={fcf_ratio:.0%}（異常偏低），改用 EPS×75% 近似"
            fcf_ps = eps_ttm * 0.75
        elif fcf_ratio > 3.0:
            fcf_note = f"⚠️ FCF/EPS={fcf_ratio:.0%}（異常偏高），可能含一次性項目"

    stype = classify(info)

    results = []
    notes = []  # 額外的備註行
    if fcf_note:
        notes.append(fcf_note)

    if stype == "一般股":
        if v := dcf(fcf_ps, g5):
            results.append(("DCF", v, f"FCF r=10% g={g5*100:.0f}%",
                f"FCF/股=${fcf_ps:.2f} → 預測{FORECAST_YEARS}年(g={g5*100:.0f}%) + 終端價值(gt={TERMINAL_GROWTH*100:.0f}%) → 折現(r={DISCOUNT_RATE*100:.0f}%)"))
        if r := pe_val(eps_ttm, sector):
            results.append(("P/E", r[0], f"EPS ${eps_ttm:.2f} × {r[1]}x",
                f"Trailing EPS ${eps_ttm:.2f} × {sector}產業平均 P/E {r[1]}x = ${r[0]:.2f}"))
        if r := peg_val(price, fwd_eps or eps_ttm, g5*100, sector):
            _eps_used = fwd_eps or eps_ttm
            _fair, _cur_peg = r
            _peg_str = f"{_cur_peg:.2f}" if _cur_peg else "N/A"
            results.append(("PEG", _fair, f"PEG=1 公允價（當前PEG={_peg_str}）",
                f"公式：P/E ÷ g% → PEG=1 時 公允P/E={g5*100:.0f}x → ${_eps_used:.2f} × {g5*100:.0f} = ${_fair:.2f}"))
    elif stype == "金融股":
        if v := excess_returns(bvps, roe):
            results.append(("ExcessRet", v, f"ROE {roe*100:.1f}%",
                f"BV ${bvps:.2f} + (ROE {roe*100:.1f}% − CoE 10%) × BV ÷ (CoE−g) = ${v:.2f}"))
        if r := pe_val(eps_ttm, sector):
            results.append(("P/E", r[0], f"EPS ${eps_ttm:.2f} × {r[1]}x",
                f"Trailing EPS ${eps_ttm:.2f} × {sector}產業平均 P/E {r[1]}x = ${r[0]:.2f}"))
        if r := pb_val(bvps, sector):
            results.append(("P/B", r[0], f"BVPS ${bvps:.2f} × {r[1]}x",
                f"每股淨值 ${bvps:.2f} × {sector}產業平均 P/B {r[1]}x = ${r[0]:.2f}"))
    elif stype == "REITs":
        if v := ddm(div, 0.03):
            results.append(("DDM", v, f"配息 ${div:.3f}",
                f"D₁ = ${div:.3f}×(1+3%) ÷ (r=8% − g=3%) = ${v:.2f}"))
        _affo = fcf_ps or (div/0.75 if div else None)
        if v := dcf(_affo, 0.04):
            results.append(("DCF", v, "AFFO r=10%",
                f"AFFO/股=${_affo:.2f} → 預測5年(g=4%) + 終端價值 → 折現(r=10%)"))
        if r := pb_val(bvps, sector):
            results.append(("P/B", r[0], f"BVPS ${bvps:.2f} × {r[1]}x",
                f"每股淨值 ${bvps:.2f} × {sector}產業平均 P/B {r[1]}x = ${r[0]:.2f}"))
    elif stype == "公用事業":
        if v := ddm(div, 0.025):
            results.append(("DDM", v, f"配息 ${div:.3f}",
                f"D₁ = ${div:.3f}×(1+2.5%) ÷ (r=8% − g=2.5%) = ${v:.2f}"))
        if v := dcf(fcf_ps, 0.04):
            results.append(("DCF", v, "FCF r=10% g=4%",
                f"FCF/股=${fcf_ps:.2f} → 預測5年(g=4%) + 終端價值(gt=3%) → 折現(r=10%)"))
        if r := pe_val(eps_ttm, sector):
            results.append(("P/E", r[0], f"EPS ${eps_ttm:.2f} × {r[1]}x",
                f"Trailing EPS ${eps_ttm:.2f} × {sector}產業平均 P/E {r[1]}x = ${r[0]:.2f}"))
    elif stype == "虧損成長股":
        if rev_ps:
            results.append(("Rev×3", rev_ps*3, "Rev/Share × 3x",
                f"每股營收 ${rev_ps:.2f} × 3x 營收倍數 = ${rev_ps*3:.2f}"))
        _g_cons = min(g5, 0.25)
        if v := dcf(fcf_ps if fcf_ps and fcf_ps > 0 else None, _g_cons):
            results.append(("DCF保守", v, f"g={_g_cons*100:.0f}%",
                f"FCF/股=${fcf_ps:.2f} → 保守成長率(g={_g_cons*100:.0f}%) → 折現(r=10%)"))
    elif stype == "週期股":
        if r := ev_ebitda_val(ebitda, net_debt, shares, sector):
            _mult = r[1]
            results.append(("EV/EBITDA", r[0], f"× {_mult}x",
                f"EBITDA × {_mult}x({sector}) − 淨負債 ÷ 流通股數 = ${r[0]:.2f}"))
        if r := pb_val(bvps, sector):
            results.append(("P/B", r[0], f"BVPS ${bvps:.2f} × {r[1]}x",
                f"每股淨值 ${bvps:.2f} × {sector}產業平均 P/B {r[1]}x = ${r[0]:.2f}"))
        if v := dcf(fcf_ps, g5):
            results.append(("DCF", v, f"g={g5*100:.0f}%",
                f"FCF/股=${fcf_ps:.2f} → 預測5年(g={g5*100:.0f}%) + 終端價值 → 折現(r=10%)"))

    vals    = [r[1] for r in results]
    fair_lo = min(vals) if vals else None
    fair_hi = max(vals) if vals else None

    # ── 合理性檢查：如果估值範圍與當前價格相差超過 10 倍，標記異常 ──
    sanity_warn = ""
    if price and fair_hi and fair_lo:
        spread_ratio = fair_hi / fair_lo if fair_lo > 0 else 999
        if spread_ratio > 10:
            sanity_warn = f"⚠️ 估值方法間差異過大（{spread_ratio:.0f}x），建議以 P/E 為主要參考"
            # 如果有 P/E 結果，用它來縮窄範圍
            pe_vals = [r[1] for r in results if r[0] == "P/E"]
            if pe_vals:
                center = pe_vals[0]
                fair_lo = max(fair_lo, center * 0.7)
                fair_hi = min(fair_hi, center * 1.3)

    rate, src = get_usd_twd()

    w52l = safe(info.get("fiftyTwoWeekLow"))
    w52h = safe(info.get("fiftyTwoWeekHigh"))
    
    # 生成股價區間圖表
    chart_path = None
    if price and w52l and w52h:
        chart_path = generate_price_chart_png(ticker_str, price, w52h, w52l)
    
    L = [
        f"📊 {ticker_str} ({name})",
        f"🏷 {stype}　🌐 {sector}　🏦 {exchange}" if exchange else f"🏷 {stype}　🌐 {sector}",
    ]
    if ccy_note:
        L.append(ccy_note)
    L.append("")
    if price:
        price_line = f"💰 當前股價：${price:.2f}"
        if w52l and w52h:
            price_line += f"　📈 52W：${w52l:.2f} — ${w52h:.2f}"
        L.append(price_line)
    L.append(f"📐 成長率 g={g5*100:.1f}%（{g_detail}）")
    for n in notes:
        L.append(n)
    L += [
        "",
        f"{'方法':<12} {'估值':>8}    說明",
        "─" * 46,
    ]
    for method, val, note, detail_text in results:
        L.append(f"{method:<12} ${val:>7.2f}    {note}")
        if detail:
            L.append(f"             └─ {detail_text}")
    L += [
        "",
        f"📌 公允區間：${fair_lo:.2f} — ${fair_hi:.2f}" if fair_lo else "📌 資料不足，無法估值",
    ]
    if sanity_warn:
        L.append(sanity_warn)
    L += [
        f"判斷：{judge(price, fair_lo, fair_hi)}",
        "",
        "─" * 42,
    ]

    # FIX: 只有實際傳入 token 數時才顯示費用
    if input_tokens or output_tokens:
        total_tok = input_tokens + output_tokens
        model = model_override or get_model()
        in_price, out_price = _get_pricing(model)
        cost_usd = (input_tokens * in_price + output_tokens * out_price) / 1_000_000
        cost_twd = cost_usd * rate
        billing = detect_billing_mode()
        if billing == "pro":
            billing_line = "📋 計費模式：Claude PRO 訂閱"
        elif billing == "fallback":
            billing_line = "⚠️ 計費模式：訂閱超量，目前改用 Claude API Token 計費"
        else:
            billing_line = "📋 計費模式：Claude API Token 計費"

        L += [
            f"🤖 使用模型：{model}",
            f"   定價：${in_price:.2f} / ${out_price:.2f} per MTok（input / output）",
            f"🔡 Token 用量：輸入 {input_tokens:,} ／ 輸出 {output_tokens:,} ／ 合計 {total_tok:,}",
            f"💵 本次查詢費用：≈ ${cost_usd:.6f} USD ≈ NT$ {cost_twd:.4f}",
            f"   （1 USD = {rate:.2f} TWD，{src}）",
            billing_line,
        ]
    else:
        L.append(f"1 USD = {rate:.2f} TWD（{src}）")

    analysis_text = "\n".join(L)
    
    # 返回分析文字和圖表路徑
    return {
        "analysis": analysis_text,
        "chart": chart_path
    }


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser(description="US Stock Fair Value Estimator")
    p.add_argument("ticker",             help="股票代號（如 AAPL）")
    p.add_argument("--input",  type=int, default=0, help="輸入 token 數（費用追蹤）")
    p.add_argument("--output", type=int, default=0, help="輸出 token 數（費用追蹤）")
    p.add_argument("--model",  type=str, default=None, help="實際使用的模型名稱（由 agent 傳入）")
    p.add_argument("--detail", action="store_true", default=True, help="顯示估值公式細節（預設開啟）")
    p.add_argument("--no-detail", dest="detail", action="store_false", help="隱藏估值公式細節")
    args = p.parse_args()
    result = run(args.ticker, args.input, args.output, detail=args.detail, model_override=args.model)
    print(result["analysis"])
    # 圖表路徑可用於外部調用（例如 message tool）
    if result["chart"]:
        print(f"# CHART_PATH: {result['chart']}")
