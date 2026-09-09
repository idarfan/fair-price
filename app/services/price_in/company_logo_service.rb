# frozen_string_literal: true

# 公司 logo 與名稱，供圖表頁首的代號徽章使用。
#
# 快取而不建資料表：logo URL 幾乎不變，30 天 TTL 已經足夠，
# 而規格 §1.3 明訂本工具不建新資料表。代價是 process 內的 MemoryStore
# 在 server 重啟後會清空，屆時第一次開圖會再打一次 profile2——
# 那是一個請求換掉一張遷移檔，划算。
#
# 抓不到就回 nil，徽章退回純文字代號。logo 是裝飾，不該讓任何流程卡住。
module PriceIn
  class CompanyLogoService
    CACHE_TTL     = 30.days
    CACHE_VERSION = 1
    CACHE_PREFIX  = "price_in:logo"

    Profile = Data.define(:logo_url, :name) do
      def logo? = logo_url.present?
    end

    def self.call(ticker) = new(ticker).call

    # 只讀快取，絕不打上游。頁面載入時用這個——規格禁止載入時產生上游請求，
    # 那條規則是為報價寫的，但「開一次頁面就多一次外部往返」的問題一模一樣。
    # 快取由 #quote endpoint（使用者按「帶入現價」）順便暖起來。
    def self.cached(ticker)
      raw = Rails.cache.read(new(ticker).send(:cache_key))
      raw.is_a?(Hash) ? Profile.new(logo_url: raw[:logo_url], name: raw[:name]) : nil
    end

    def initialize(ticker)
      @ticker = ticker.to_s.strip.upcase
    end

    def call
      return blank if @ticker.blank?

      cached = Rails.cache.read(cache_key)
      return from_hash(cached) if cached.is_a?(Hash)

      profile = fetch
      Rails.cache.write(cache_key, profile.to_h, expires_in: CACHE_TTL)
      profile
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::CompanyLogoService] #{@ticker}: #{e.class}: #{e.message}")
      blank
    end

    private

    def cache_key = "#{CACHE_PREFIX}:v#{CACHE_VERSION}:#{@ticker}"

    # 存 Hash 不存 Data：Data 的 Marshal 綁死欄位數量，改一個欄位就在部署
    # 當下引爆（2026-09-07 QuoteFetcher 的教訓）。
    def from_hash(raw) = Profile.new(logo_url: raw[:logo_url], name: raw[:name])

    def fetch
      data = FinnhubService.new.profile(@ticker)
      return blank unless data.is_a?(Hash)

      # 空字串也當成沒有：Finnhub 對部分 ETF 會回 logo: ""。
      Profile.new(logo_url: data["logo"].presence, name: data["name"].presence)
    end

    def blank = Profile.new(logo_url: nil, name: nil)
  end
end
