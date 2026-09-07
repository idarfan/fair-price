# frozen_string_literal: true

# 同業本益比區間。上游沒有「產業平均本益比」這種欄位，所以自己算：
# 取 Finnhub 的同業清單，逐一抓 peTTM，回傳中位數附近的區間。
#
# 為什麼回區間而不是單一平均：半導體同業的本益比分散極大（本檔實測 AVGO 44 倍、
# MRVL 74 倍），算術平均會被少數極端值拉走。用四分位距描述「大多數同業落在哪裡」
# 比一個平均數誠實。
#
# 口徑問題與 peTTM 相同——上游沒說是 GAAP 還是 non-GAAP，畫面必須標註。
module PriceIn
  class PeerMultipleService
    CACHE_TTL     = 12.hours   # 同業本益比不需要即時，拉長 TTL 省上游額度
    CACHE_VERSION = 2          # 欄位結構一變就 +1，見 QuoteFetcher 的說明
    CACHE_PREFIX  = "price_in:peers"
    MAX_PEERS    = 8          # 同業清單可能十幾檔，全抓會吃光 API 額度
    MIN_SAMPLE   = 3          # 樣本太少算不出有意義的區間

    Result = Data.define(:low, :high, :sample_size, :peers) do
      def available? = !low.nil? && !high.nil?
    end

    def self.call(ticker) = new(ticker).call

    def initialize(ticker)
      @ticker = ticker.to_s.strip.upcase
    end

    def call
      return empty if @ticker.blank?

      cached = Rails.cache.read(cache_key)
      return from_hash(cached) if cached.is_a?(Hash)

      result = compute
      Rails.cache.write(cache_key, result.to_h, expires_in: CACHE_TTL) if result.available?
      result
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::PeerMultipleService] #{@ticker} 同業本益比失敗：#{e.class}: #{e.message}")
      empty
    end

    private

    def cache_key = "#{CACHE_PREFIX}:v#{CACHE_VERSION}:#{@ticker}"

    # 同樣存 Hash 不存 Data，理由見 QuoteFetcher。
    def from_hash(raw)
      Result.new(low: raw[:low], high: raw[:high],
                 sample_size: raw[:sample_size].to_i, peers: Array(raw[:peers]))
    end

    def compute
      peers = fetch_peers
      return empty if peers.empty?

      values = fetch_multiples(peers)
      return empty if values.size < MIN_SAMPLE

      sorted = values.map { |_, v| v }.sort
      Result.new(low: quantile(sorted, 0.25), high: quantile(sorted, 0.75),
                 sample_size: sorted.size, peers: values.map(&:first))
    end

    def fetch_peers
      client = FinnhubService.new
      list   = client.peers(@ticker)
      return [] unless list.is_a?(Array)

      # 清單通常含自己，排掉——拿自己的本益比當「同業平均」是循環論證。
      list.map(&:to_s).map(&:upcase).uniq.reject { |s| s == @ticker }.first(MAX_PEERS)
    end

    # 平行抓取。序列跑八檔在慢速回應下會讓使用者盯著轉圈超過十秒。
    def fetch_multiples(peers)
      threads = peers.map do |symbol|
        Thread.new do
          metrics = FinnhubService.new.basic_metrics(symbol)
          value   = metrics.is_a?(Hash) ? metrics.dig("metric", "peTTM") : nil
          value.is_a?(Numeric) && value.positive? ? [ symbol, value.to_f ] : nil
        rescue StandardError
          nil
        end
      end
      threads.filter_map(&:value)
    end

    # 線性內插分位數。樣本只有三到八個，用最簡單的定義就好。
    def quantile(sorted, fraction)
      return nil if sorted.empty?

      pos   = (sorted.size - 1) * fraction
      lower = sorted[pos.floor]
      upper = sorted[pos.ceil]
      lower + ((upper - lower) * (pos - pos.floor))
    end

    def empty = Result.new(low: nil, high: nil, sample_size: 0, peers: [])
  end
end
