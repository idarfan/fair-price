# frozen_string_literal: true

# Fetches VIX index from Yahoo Finance (Finnhub free tier doesn't support ^VIX)
class VixService
  YAHOO_URL = "https://query1.finance.yahoo.com/v8/finance/chart/%5EVIX"

  def fetch
    response = HTTParty.get(
      YAHOO_URL,
      query:   { interval: "1d", range: "1d" },
      headers: { "User-Agent" => "Mozilla/5.0" },
      timeout: 8
    )
    return nil unless response.success?

    response.parsed_response.dig("chart", "result", 0, "meta", "regularMarketPrice")&.to_f
  rescue StandardError => e
    Rails.logger.warn("[VixService] fetch failed: #{e.message}")
    nil
  end
end
