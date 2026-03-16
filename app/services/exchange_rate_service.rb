class ExchangeRateService
  include HTTParty

  CACHE_PATH = "/tmp/.fairprice_fx_cache"
  CACHE_TTL  = 3600
  FALLBACK   = 32.50

  URLS = %w[
    https://open.er-api.com/v6/latest/USD
    https://api.exchangerate-api.com/v4/latest/USD
  ].freeze

  def self.usd_twd
    all_rates.first["TWD"]&.to_f || FALLBACK
  end

  def self.all_rates
    new.send(:fetch_rates)
  end

  private

  def fetch_rates
    cached = read_cache
    return [cached, :cache] if cached

    URLS.each do |url|
      response = self.class.get(url, headers: { "User-Agent" => "FairPrice/2.0" }, timeout: 4)
      next unless response.success?

      rates = response.parsed_response["rates"] ||
              response.parsed_response["conversion_rates"] || {}
      next if rates.empty?

      write_cache(rates)
      return [rates, :live]
    rescue
      next
    end

    [{}, :failed]
  end

  def read_cache
    return nil unless File.exist?(CACHE_PATH)
    return nil if Time.now - File.mtime(CACHE_PATH) > CACHE_TTL

    JSON.parse(File.read(CACHE_PATH))
  rescue
    nil
  end

  def write_cache(rates)
    File.write(CACHE_PATH, rates.to_json)
  rescue
    nil
  end
end
