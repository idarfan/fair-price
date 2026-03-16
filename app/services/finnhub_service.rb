# frozen_string_literal: true

class FinnhubService
  BASE_URL = "https://finnhub.io/api/v1"

  def initialize(api_key: ENV.fetch("FINNHUB_API_KEY"))
    @api_key = api_key
  end

  def market_status
    get("/stock/market-status", exchange: "US")
  end

  def quote(symbol)
    get("/quote", symbol: symbol.upcase)
  end

  def market_news(count: 5)
    items = get("/news", category: "general") || []
    items.first(count)
  end

  def company_news(symbol, from_date:, to_date:)
    items = get("/company-news", symbol: symbol.upcase, from: from_date, to: to_date) || []
    items.first(8)
  end

  def earnings_calendar(from_date:, to_date:)
    result = get("/calendar/earnings", from: from_date, to: to_date)
    result&.dig("earningsCalendar") || []
  end

  def basic_metrics(symbol)
    get("/stock/metric", symbol: symbol.upcase, metric: "all")
  end

  def candles(symbol, from:, to:, resolution: "D")
    get("/stock/candle", symbol: symbol.upcase, resolution: resolution,
                         from: from.to_i, to: to.to_i)
  end

  private

  def get(path, params = {})
    response = HTTParty.get(
      "#{BASE_URL}#{path}",
      query: params.merge(token: @api_key),
      timeout: 10
    )
    return nil unless response.success?

    response.parsed_response
  rescue HTTParty::Error, Net::ReadTimeout, SocketError => e
    Rails.logger.warn("[FinnhubService] #{path} failed: #{e.message}")
    nil
  end
end
