# frozen_string_literal: true

# Fetches stock data from Yahoo Finance (free, no API key required)
class YahooFinanceService
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

    meta    = result["meta"] || {}
    closes  = (result.dig("indicators", "quote", 0, "close")  || []).compact.map(&:to_f)
    volumes = (result.dig("indicators", "quote", 0, "volume") || []).compact.map(&:to_i)

    {
      high_52w:   meta["fiftyTwoWeekHigh"]&.to_f&.round(2),
      low_52w:    meta["fiftyTwoWeekLow"]&.to_f&.round(2),
      volume:     meta["regularMarketVolume"]&.to_i,
      change_pct: compute_change_pct(meta),
      closes:     closes,
      volumes:    volumes
    }
  rescue StandardError => e
    Rails.logger.warn("[YahooFinance] #{symbol} failed: #{e.message}")
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
      institutions_pct:       breakdown.dig("institutionsPercentHeld", "raw"),
      insiders_pct:           breakdown.dig("insidersPercentHeld", "raw"),
      institutions_float_pct: breakdown.dig("institutionsFloatPercentHeld", "raw"),
      institutions_count:     breakdown.dig("numberOfInstitutions", "raw")
    }

    top_holders = ownership_raw.first(10).map do |h|
      {
        name:        h.dig("organization") || "—",
        pct_held:    h.dig("pctHeld", "raw"),
        value:       h.dig("value", "raw"),
        report_date: h.dig("reportDate", "fmt")
      }
    end

    { summary: summary, top_holders: top_holders, source: "Yahoo Finance" }
  rescue StandardError => e
    Rails.logger.warn("[YahooFinance] holders #{symbol} failed: #{e.message}")
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
  rescue StandardError => e
    Rails.logger.warn("[YahooFinance] fetch_crumb failed: #{e.message}")
    [ nil, nil ]
  end

  def empty_result
    { high_52w: nil, low_52w: nil, volume: nil, change_pct: nil, closes: [], volumes: [] }
  end

  def empty_holders
    { summary: nil, top_holders: [] }
  end
end
