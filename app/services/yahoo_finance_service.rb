# frozen_string_literal: true

# Fetches stock data from Yahoo Finance (free, no API key required)
class YahooFinanceService
  HTTP_ERRORS = [
    HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout,
    SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
  ].freeze
  BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart"
  HEADERS  = { "User-Agent" => "Mozilla/5.0" }.freeze

  # Returns { high_52w:, low_52w:, volume:, change_pct:, closes: [] }
  def chart(symbol, range: "1y", interval: "1d")
    response = HTTParty.get(
      "#{BASE_URL}/#{CGI.escape(symbol)}",
      query:   { interval: interval, range: range },
      headers: HEADERS,
      timeout: 10
    )
    return empty_result unless response.success?

    result = response.parsed_response.dig("chart", "result", 0)
    return empty_result unless result

    meta       = result["meta"] || {}
    quote = result.dig("indicators", "quote", 0) || {}
    raw_ts  = result["timestamp"] || []
    raw_o   = quote["open"]   || []
    raw_h   = quote["high"]   || []
    raw_l   = quote["low"]    || []
    raw_c   = quote["close"]  || []
    raw_v   = quote["volume"] || []

    # Zip and drop bars where close is nil
    zipped = raw_ts.zip(raw_o, raw_h, raw_l, raw_c, raw_v).select { |_, _, _, _, c, _| c }

    {
      high_52w:   meta["fiftyTwoWeekHigh"]&.to_f&.round(2),
      low_52w:    meta["fiftyTwoWeekLow"]&.to_f&.round(2),
      volume:     meta["regularMarketVolume"]&.to_i,
      change_pct: compute_change_pct(meta),
      timestamps: zipped.map { |ts, *| ts.to_i },
      opens:      zipped.map { |_, o, *| o&.to_f },
      highs:      zipped.map { |_, _, h, *| h&.to_f },
      lows:       zipped.map { |_, _, _, l, *| l&.to_f },
      closes:     zipped.map { |_, _, _, _, c, _| c.to_f },
      volumes:    zipped.map { |_, _, _, _, _, v| v.to_i }
    }
  rescue *HTTP_ERRORS => e
    Rails.logger.warn("[YahooFinance] chart #{symbol}: #{e.class} #{e.message}")
    empty_result
  end

  CRUMB_URL      = "https://query2.finance.yahoo.com/v1/test/getcrumb"
  SUMMARY_URL    = "https://query2.finance.yahoo.com/v10/finance/quoteSummary"
  YF_HOME_URL    = "https://finance.yahoo.com"
  # Accept text/html 才能拿到 A1 session cookie
  HOLDER_HEADERS = {
    "User-Agent"      => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                         "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language" => "en-US,en;q=0.9"
  }.freeze

  # Returns { summary:, top_holders:, source: "Yahoo Finance" } or nil on failure
  def holders(symbol)
    crumb, cookie = fetch_crumb
    return nil unless crumb

    response = HTTParty.get(
      "#{SUMMARY_URL}/#{CGI.escape(symbol.upcase)}",
      query:   { modules: "institutionOwnership,majorHoldersBreakdown", crumb: crumb },
      headers: HOLDER_HEADERS.merge("Cookie" => cookie),
      timeout: 10
    )
    unless response.success?
      Rails.logger.warn("[YahooFinance] holders #{symbol} HTTP #{response.code}")
      return nil
    end

    result = response.parsed_response.dig("quoteSummary", "result", 0)
    unless result
      Rails.logger.warn("[YahooFinance] holders #{symbol} no result: #{response.body.to_s.first(200)}")
      return nil
    end

    breakdown     = result.dig("majorHoldersBreakdown") || {}
    ownership_raw = result.dig("institutionOwnership", "ownershipList") || []

    summary = {
      institutions_pct:       pct_to_f(breakdown.dig("institutionsPercentHeld",      "raw")),
      insiders_pct:           pct_to_f(breakdown.dig("insidersPercentHeld",          "raw")),
      institutions_float_pct: pct_to_f(breakdown.dig("institutionsFloatPercentHeld", "raw")),
      institutions_count:     breakdown.dig("institutionsCount", "raw")
    }

    top_holders = ownership_raw.first(10).map do |h|
      {
        name:        h.dig("organization") || "—",
        pct_held:    pct_to_f(h.dig("pctHeld",   "raw")),
        value:       h.dig("value", "raw"),
        report_date: h.dig("reportDate", "fmt"),
        pct_change:  pct_to_f(h.dig("pctChange", "raw"))
      }
    end

    { summary: summary, top_holders: top_holders, source: "Yahoo Finance" }
  rescue *HTTP_ERRORS => e
    Rails.logger.warn("[YahooFinance] holders #{symbol}: #{e.class} #{e.message}")
    nil
  end

  private

  def compute_change_pct(meta)
    pct = meta["regularMarketChangePercent"]&.to_f
    return pct.round(2) if pct

    price = meta["regularMarketPrice"]&.to_f
    prev  = meta["chartPreviousClose"]&.to_f
    return nil if price.nil? || prev.nil? || prev.zero?

    ((price - prev) / prev * 100).round(2)
  end

  def fetch_crumb
    # Step 1：先訪問首頁取得 A1 session cookie
    home_resp = HTTParty.get(YF_HOME_URL, headers: HOLDER_HEADERS,
                             timeout: 10, follow_redirects: false)
    cookie = home_resp.headers["set-cookie"].to_s.split(";").first
    return [ nil, nil ] if cookie.blank?

    # Step 2：用 cookie 取得 crumb
    crumb_resp = HTTParty.get(CRUMB_URL,
                              headers: HOLDER_HEADERS.merge("Cookie" => cookie),
                              timeout: 8)
    return [ nil, nil ] unless crumb_resp.success?

    crumb = crumb_resp.body.to_s.strip
    return [ nil, nil ] if crumb.empty?

    [ crumb, cookie ]
  rescue *HTTP_ERRORS => e
    Rails.logger.warn("[YahooFinance] fetch_crumb: #{e.class} #{e.message}")
    [ nil, nil ]
  end

  def empty_result
    { high_52w: nil, low_52w: nil, volume: nil, change_pct: nil,
      timestamps: [], opens: [], highs: [], lows: [], closes: [], volumes: [] }
  end

  def empty_holders
    { summary: nil, top_holders: [] }
  end

  # Yahoo Finance 回傳 0~1 的小數（0.0929 = 9.29%），乘以 100 轉成百分比
  def pct_to_f(val)
    val.nil? ? nil : (val.to_f * 100).round(4)
  end
end
