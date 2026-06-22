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

  def profile(symbol)
    get("/stock/profile2", symbol: symbol.upcase)
  end

  def basic_metrics(symbol)
    get("/stock/metric", symbol: symbol.upcase, metric: "all")
  end

  def candles(symbol, from:, to:, resolution: "D")
    get("/stock/candle", symbol: symbol.upcase, resolution: resolution,
                         from: from.to_i, to: to.to_i)
  end

  private

  MAX_RETRIES = 2

  def get(path, params = {})
    retries = 0
    begin
      response = HTTParty.get(
        "#{BASE_URL}#{path}",
        query: params.merge(token: @api_key),
        timeout: 10
      )
      return nil unless response.success?

      response.parsed_response
    rescue HTTParty::Error, Net::ReadTimeout, Errno::ECONNRESET,
           OpenSSL::SSL::SSLError, SocketError => e
      if retries < MAX_RETRIES
        retries += 1
        Rails.logger.warn("[FinnhubService] #{path} failed (attempt #{retries}/#{MAX_RETRIES}): #{e.message}, retrying in #{retries}s...")
        sleep(retries)
        retry
      end
      Rails.logger.warn("[FinnhubService] #{path} failed after #{MAX_RETRIES} retries: #{e.message}")
      nil
    end
  end
end
