class ExchangeRateService
  include HTTParty

  CACHE_KEY = "exchange_rates_usd"
  CACHE_TTL = 3600
  FALLBACK  = 32.50

  URLS = %w[
    https://open.er-api.com/v6/latest/USD
    https://api.exchangerate-api.com/v4/latest/USD
  ].freeze

  def self.usd_twd
    all_rates.first["TWD"]&.to_f || FALLBACK
  end

  # 回傳 1 USD 對應目標幣別的匯率（例如 EUR 約 0.87）。
  # 用途：把非 USD 的每股/總額數字換算回 USD。查無匯率時回傳 nil（呼叫端須自行決定 fallback）。
  def self.rate_to_usd(currency)
    return 1.0 if currency.to_s.upcase == "USD"

    all_rates.first[currency.to_s.upcase]&.to_f
  end

  def self.all_rates
    new.send(:fetch_rates)
  end

  private

  def fetch_rates
    cached = Rails.cache.read(CACHE_KEY)
    return [ cached, :cache ] if cached

    URLS.each do |url|
      response = self.class.get(url, headers: { "User-Agent" => "FairPrice/2.0" }, timeout: 4)
      next unless response.success?

      rates = response.parsed_response["rates"] ||
              response.parsed_response["conversion_rates"] || {}
      next if rates.empty?

      Rails.cache.write(CACHE_KEY, rates, expires_in: CACHE_TTL.seconds)
      return [ rates, :live ]
    rescue => e
      Rails.logger.warn("[ExchangeRateService] #{e.class}: #{e.message}")
      next
    end

    [ {}, :failed ]
  end
end
