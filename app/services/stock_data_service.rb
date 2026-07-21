class StockDataService
  include HTTParty

  NotFoundError  = Class.new(StandardError)
  ConfigError    = Class.new(StandardError)

  BASE_URL   = "https://finnhub.io/api/v1"
  USER_AGENT = "FairPrice/2.0"

  # Finnhub finnhubIndustry → 我們的 sector 分類
  SECTOR_MAP = [
    [ /bank|insurance|financial|thrift|mortgage|capital market|brokerage/i, "Financial Services" ],
    [ /real estate|reit/i,                                                    "Real Estate" ],
    [ /electric util|gas util|water util|multi.util|independent power|util/i, "Utilities" ],
    [ /oil|petroleum|gas & consumable|energy/i,                               "Energy" ],
    [ /steel|mining|metal|chemical|copper|coal|material|aluminum/i,           "Basic Materials" ],
    [ /software|semiconductor|hardware|internet|tech|computer|electron/i,     "Technology" ],
    [ /health|pharma|biotech|medical|hospital|life science/i,                 "Healthcare" ],
    [ /telecom|media|communication|entertainment|broadcast/i,                 "Communication Services" ],
    [ /retail|automobile|hotel|restaurant|apparel|leisure|consumer discret/i, "Consumer Cyclical" ],
    [ /food|beverage|tobacco|household|consumer staple|supermarket/i,         "Consumer Defensive" ],
    [ /aerospace|defense|industrial|transport|airline|machinery|construct/i,  "Industrials" ]
  ].freeze

  def self.fetch(ticker)
    new(ticker).fetch
  end

  def initialize(ticker)
    @ticker  = ticker.upcase
    @api_key = self.class.resolve_api_key
  end

  def self.resolve_api_key
    key = ENV["FINNHUB_API_KEY"].presence
    raise ConfigError, "請設定 FINNHUB_API_KEY 環境變數（至 https://finnhub.io 免費申請）" if key.blank?

    key
  end

  def fetch
    profile, quote, metrics, recommend = fetch_parallel

    has_name  = profile.is_a?(Hash) && profile["name"].present?
    has_price = safe_float(quote.is_a?(Hash) ? quote["c"] : nil)&.positive?

    # ETF 等品種 Finnhub profile2 可能無 name，但 quote 仍有效（如 TQQQ、SQQQ）
    raise NotFoundError, "找不到股票：#{@ticker}（請確認代號正確）" unless has_name || has_price

    parse(profile || {}, quote || {}, metrics, recommend)
  end

  private

  # ── Parallel API Calls ────────────────────────────────────────

  def fetch_parallel
    threads = {
      profile:    Thread.new { api_get("/stock/profile2",      symbol: @ticker) },
      quote:      Thread.new { api_get("/quote",               symbol: @ticker) },
      metrics:    Thread.new { api_get("/stock/metric",        symbol: @ticker, metric: "all") },
      recommend:  Thread.new { api_get_safe("/stock/recommendation", symbol: @ticker) }
    }
    [ threads[:profile].value, threads[:quote].value,
     threads[:metrics].value, threads[:recommend].value ]
  end

  def api_get(path, params = {})
    response = self.class.get(
      "#{BASE_URL}#{path}",
      query:   params.merge(token: @api_key),
      headers: { "User-Agent" => USER_AGENT },
      timeout: 12
    )

    raise NotFoundError, "Finnhub 回應錯誤（HTTP #{response.code}）" unless response.success?

    response.parsed_response
  rescue SocketError, Timeout::Error, Net::OpenTimeout => e
    raise NotFoundError, "無法連線至 Finnhub：#{e.message}"
  end

  # 失敗時回傳 nil 而非拋出例外（用於選用性資料）
  def api_get_safe(path, params = {})
    api_get(path, params)
  rescue NotFoundError
    nil
  end

  # ── Data Parsing ──────────────────────────────────────────────

  def parse(profile, quote, metrics_resp, recommend_resp)
    m        = (metrics_resp || {})["metric"] || {}
    currency = (profile["currency"] || "USD").upcase

    # Finnhub 對雙掛牌 ADR（如 NOK）：/quote 回傳掛牌交易所的價格（美股 ticker 恆為 USD），
    # 但 /stock/profile2、/stock/metric 回傳公司財報原始幣別（如 Nokia 用 EUR）。
    # 若不换算，會出現「USD 股價 ÷ EUR 每股盈餘」的幣別混用，公允價值嚴重失真。
    fx = currency == "USD" ? 1.0 : ExchangeRateService.rate_to_usd(currency)
    currency_note = nil
    if currency != "USD"
      currency_note = fx ? "原始財報幣別 #{currency}，已依匯率 1 USD ≈ #{fx.round(4)} #{currency} 換算為 USD" :
                            "原始財報幣別 #{currency}，查無即時匯率，數值未換算，可能與 USD 股價不一致"
      fx ||= 1.0
    end

    # shareOutstanding is in millions
    shares = safe_float(profile["shareOutstanding"])&.*(1_000_000)

    # Per-share metrics × shares = totals（先換算成 USD 再乘股數）
    rev_ps   = conv(safe_float(m["revenuePerShareTTM"]), fx)
    fcf_ps   = conv(safe_float(m["freeCashFlowPerShareTTM"]), fx)
    ebitd_ps = conv(safe_float(m["ebitdPerShareTTM"]), fx)

    # ROE & growth: Finnhub returns as percentage (e.g., 120.5 means 120.5%)
    roe            = pct_to_ratio(m["roeTTM"])
    eps_growth     = pct_to_ratio(m["epsGrowthTTMYoy"])
    rev_growth     = pct_to_ratio(m["revenueGrowthTTMYoy"])
    eps_q_growth   = pct_to_ratio(m["epsGrowthQuarterlyYoy"])

    industry = profile["finnhubIndustry"].to_s

    {
      symbol:                    @ticker,
      name:                      profile["name"] || @ticker,
      sector:                    map_sector(industry),
      industry:                  industry.presence,
      exchange:                  profile["exchange"],
      currency:                  "USD",
      financial_currency:        currency,
      currency_note:             currency_note,
      current_price:             safe_float(quote["c"]),
      shares_outstanding:        shares,
      eps_ttm:                   conv(safe_float(m["epsTTM"]), fx),
      forward_eps:               nil,
      book_value:                conv(safe_float(m["bookValuePerShareQuarterly"]) ||
                                 safe_float(m["bookValuePerShareAnnual"]), fx),
      roe:                       roe,
      dividend_rate:             conv(safe_float(m["dividendPerShareTTM"]) ||
                                 safe_float(m["dividendPerShareAnnual"]), fx),
      free_cashflow:             mul(fcf_ps, shares),
      total_revenue:             mul(rev_ps, shares),
      ebitda:                    mul(ebitd_ps, shares),
      total_debt:                nil,
      total_cash:                nil,
      earnings_growth:           eps_growth,
      revenue_growth:            rev_growth,
      earnings_quarterly_growth: eps_q_growth,
      day_low:                   safe_float(quote["l"]),
      day_high:                  safe_float(quote["h"]),
      fifty_two_week_low:        conv(safe_float(m["52WeekLow"]), fx),
      fifty_two_week_high:       conv(safe_float(m["52WeekHigh"]), fx),
      analyst_consensus:         parse_recommendations(recommend_resp)
    }
  end

  def map_sector(industry)
    SECTOR_MAP.each do |pattern, sector|
      return sector if industry.match?(pattern)
    end
    industry.presence || "Unknown"
  end

  # ── Helpers ───────────────────────────────────────────────────

  def safe_float(value)
    return nil if value.nil?

    f = value.to_f
    (f.nan? || f.infinite?) ? nil : f
  end

  def mul(a, b)
    (a && b) ? a * b : nil
  end

  # 將原始財報幣別數值換算為 USD：amount(原幣別) / (1 USD 兌原幣別匯率)
  def conv(value, fx)
    return nil if value.nil?

    value / fx
  end

  def pct_to_ratio(value)
    f = safe_float(value)
    f ? f / 100.0 : nil
  end

  def parse_recommendations(resp)
    return nil unless resp.is_a?(Array) && resp.any?

    latest = resp.first
    strong_buy  = latest["strongBuy"].to_i
    buy         = latest["buy"].to_i
    hold        = latest["hold"].to_i
    sell        = latest["sell"].to_i
    strong_sell = latest["strongSell"].to_i
    total = strong_buy + buy + hold + sell + strong_sell
    return nil if total.zero?

    # 加權評分：StrongBuy=5, Buy=4, Hold=3, Sell=2, StrongSell=1
    score = (strong_buy * 5 + buy * 4 + hold * 3 + sell * 2 + strong_sell * 1).to_f / total

    {
      strong_buy:  strong_buy,
      buy:         buy,
      hold:        hold,
      sell:        sell,
      strong_sell: strong_sell,
      total:       total,
      score:       score.round(2),       # 1.0~5.0
      rating:      consensus_rating(score),
      period:      latest["period"]
    }
  end

  def consensus_rating(score)
    if    score >= 4.5 then "強力買入"
    elsif score >= 3.5 then "買入"
    elsif score >= 2.5 then "持有"
    elsif score >= 1.5 then "賣出"
    else                    "強力賣出"
    end
  end
end
