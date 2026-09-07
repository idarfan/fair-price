# frozen_string_literal: true

# 輸入代號按一下就帶入現價，抓不到也不能卡住使用者。
#
# 回股價、報價時間，以及目前的 TTM 本益比。
#
# pe_ttm 的來歷值得寫清楚：2026-09-07 曾因「上游沒有欄位說明 peTTM 是 GAAP 還是
# non-GAAP」而整組移除，同日依使用者要求加回來作為輸入時的對照參考。
# 口徑問題並沒有被解決，只是改由畫面明確標註「口徑未標示」，讓使用者自己判斷，
# 而不是由系統假裝它是個權威數字。GAAP 與 non-GAAP 的 EPS 常差到倍數等級。
module PriceIn
  class QuoteFetcher
    CACHE_TTL    = 15.minutes
    # 版本號隨快取內容的欄位結構變動而 +1。
    #
    # 教訓：2026-09-07 把 Result 從「單一 pe_ttm」改成「pe 區間」之後，快取裡
    # 舊結構的物件反序列化撞上新結構，直接 TypeError → 500。使用者看到的是
    # 「報價格式無法解析」，跟真正的原因毫無關係。改欄位卻沒換 key，等於在
    # 部署當下埋一顆定時炸彈。
    CACHE_VERSION = 3
    CACHE_PREFIX  = "price_in:quote"

    # 本益比一律是區間，不是單點。
    #
    # 理由：本益比 = 股價 ÷ EPS，而股價當天一直在動。MRVL 實測當日最低 210.87、
    # 最高 223.67，同一個 EPS 除下去就是 69.59 到 73.82 倍——差了四倍多。
    # 只報一個數字等於把「那一瞬間的成交價」講成「這家公司的估值」。
    Range = Data.define(:low, :high, :current) do
      def available? = !current.nil?
    end

    # 分析師 EPS 預測區間。low／high 是分歧範圍不是平均值——
    # 圖 A 的色帶要畫的正是分歧程度，拿平均值會變成一條線。
    Estimate = Data.define(:low, :high, :avg, :analysts, :end_date) do
      def available? = !low.nil? && !high.nil?
    end

    Result = Data.define(:ok, :price, :as_of, :eps_ttm, :pe, :forward_pe,
                         :peer_low, :peer_high, :peer_sample,
                         :eps_estimate, :eps_estimate_next, :error_code) do
      def ok? = ok

      def error_message
        case error_code
        when :not_found      then "查無此代號"
        when :rate_limited   then "報價來源忙碌中，請稍後再試，或直接手動輸入"
        else                      "暫時取不到報價，請手動輸入"
        end
      end
    end

    def self.call(ticker) = new(ticker).call

    def initialize(ticker)
      @ticker = ticker.to_s.strip.upcase
    end

    def call
      return failure(:not_found) if @ticker.blank?

      cached = read_cache
      return cached if cached

      result = fetch_from_upstream
      # 只快取成功的結果。把失敗也快取起來，會讓使用者在上游恢復後
      # 還要再等 15 分鐘才抓得到價。
      Rails.cache.write(cache_key, serialize(result), expires_in: CACHE_TTL) if result.ok?
      result
    end

    private

    def cache_key = "#{CACHE_PREFIX}:v#{CACHE_VERSION}:#{@ticker}"

    # Data#to_h 是淺層的：巢狀的 pe／forward_pe 會原封不動留成 Data 物件，
    # 存進快取就把「不要存 Data」這條規則從後門破壞掉。兩層都要自己攤平。
    def serialize(result)
      result.to_h.merge(
        pe: result.pe.to_h, forward_pe: result.forward_pe.to_h,
        eps_estimate: result.eps_estimate.to_h, eps_estimate_next: result.eps_estimate_next.to_h
      )
    end

    # 快取存 Hash 而不是 Data 物件。Data／Struct 的 Marshal 綁死欄位數量，
    # 換一個欄位就整個炸開；Hash 缺鍵只會得到 nil，最壞情況是少顯示一個數字。
    #
    # 外面再包一層 rescue：版本號已經擋掉一般情況，但快取本來就是可以壞掉的東西，
    # 讀不動就當作沒有，重抓一次，絕不讓它變成使用者看到的 500。
    def read_cache
      raw = Rails.cache.read(cache_key)
      return nil unless raw.is_a?(Hash)

      Result.new(
        ok: raw[:ok], price: raw[:price], as_of: raw[:as_of], eps_ttm: raw[:eps_ttm],
        pe: to_range(raw[:pe]), forward_pe: to_range(raw[:forward_pe]),
        peer_low: raw[:peer_low], peer_high: raw[:peer_high],
        peer_sample: raw[:peer_sample],
        eps_estimate: to_estimate(raw[:eps_estimate]),
        eps_estimate_next: to_estimate(raw[:eps_estimate_next]),
        error_code: raw[:error_code]
      )
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::QuoteFetcher] 快取讀取失敗，改為重抓：#{e.class}: #{e.message}")
      Rails.cache.delete(cache_key)
      nil
    end

    def to_range(raw)
      return Range.new(low: nil, high: nil, current: nil) unless raw.is_a?(Hash)

      Range.new(low: raw[:low], high: raw[:high], current: raw[:current])
    end

    def fetch_from_upstream
      quote, status = FinnhubService.new.quote_with_status(@ticker)

      return failure(:not_found)    if status == 404
      return failure(:rate_limited) if status == 429
      return failure(:upstream_error) if quote.nil?

      price = quote["c"].to_f
      # Finnhub 對查無的代號不回 404，而是回一組全 0 的報價。
      # 只看 HTTP 狀態碼會把「查無此代號」誤判成「這檔股票值 0 元」。
      return failure(:not_found) unless price.positive?

      metrics   = fetch_metrics
      peers     = PeerMultipleService.call(@ticker)
      estimates = fetch_estimates
      day_low   = positive_float(quote["l"])
      day_high  = positive_float(quote["h"])

      Result.new(
        ok: true, price: price, as_of: parse_timestamp(quote["t"]),
        eps_ttm:     metrics[:eps_ttm],
        pe:          build_range(metrics[:eps_ttm], price, day_low, day_high),
        forward_pe:  build_range(forward_eps(price, metrics[:forward_pe]), price, day_low, day_high),
        peer_low:    peers.low,
        peer_high:   peers.high,
        peer_sample: peers.sample_size,
        eps_estimate:      estimates[:current_year],
        eps_estimate_next: estimates[:next_year],
        error_code:  nil
      )
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::QuoteFetcher] #{@ticker} 取價失敗：#{e.class}: #{e.message}")
      failure(:upstream_error)
    end

    # 本益比抓不到不算失敗：公司過去 12 個月虧損就沒有本益比，
    # 上游也可能單純沒給這個欄位。任一情況都回 nil，畫面顯示破折號。
    # 兩個數字同一次呼叫取回，不要為了 forwardPE 再打一次上游。
    def fetch_metrics
      metrics = FinnhubService.new.basic_metrics(@ticker)
      bag     = metrics.is_a?(Hash) ? metrics["metric"] : nil
      return { pe_ttm: nil, forward_pe: nil } unless bag.is_a?(Hash)

      {
        eps_ttm:    positive_float(bag["epsTTM"]),
        forward_pe: positive_float(bag["forwardPE"])
      }
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::QuoteFetcher] #{@ticker} 取本益比失敗：#{e.class}: #{e.message}")
      { eps_ttm: nil, forward_pe: nil }
    end

    # 分析師預測抓不到不算失敗：這是選填欄位的輔助，
    # 使用者本來就可以自己查了填。
    def fetch_estimates
      raw = YahooFinanceService.new.eps_estimates(@ticker)
      return { current_year: blank_estimate, next_year: blank_estimate } unless raw.is_a?(Hash)

      { current_year: to_estimate(raw[:current_year]), next_year: to_estimate(raw[:next_year]) }
    rescue StandardError => e
      Rails.logger.warn("[PriceIn::QuoteFetcher] #{@ticker} 取 EPS 預測失敗：#{e.class}: #{e.message}")
      { current_year: blank_estimate, next_year: blank_estimate }
    end

    def to_estimate(raw)
      return blank_estimate unless raw.is_a?(Hash)

      Estimate.new(low: raw[:low], high: raw[:high], avg: raw[:avg],
                   analysts: raw[:analysts], end_date: raw[:end_date])
    end

    def blank_estimate = Estimate.new(low: nil, high: nil, avg: nil, analysts: nil, end_date: nil)

    # 三個數字全部由「同一個 EPS 除不同價格」算出，內部一致且使用者可以自己驗算。
    # 不直接用上游的 peTTM：它是上游在某個時點用某個價格算的，與我們手上的
    # 當日高低價對不起來，三個數字並排時會出現「現價本益比落在區間之外」的怪象。
    def build_range(eps, price, day_low, day_high)
      return Range.new(low: nil, high: nil, current: nil) if eps.nil? || eps.zero?

      Range.new(
        low:     day_low  ? day_low  / eps : nil,
        high:    day_high ? day_high / eps : nil,
        current: price / eps
      )
    end

    # 上游只給 forwardPE 這個比值，沒給預估 EPS。用現價反解出來，
    # 再拿它去除當日高低價，就能得到與 TTM 同一套算法的區間。
    def forward_eps(price, forward_pe)
      return nil if forward_pe.nil? || forward_pe.zero?

      price / forward_pe
    end

    # 負本益比代表虧損，拿來當估值錨點沒有意義，一律當成沒有。
    def positive_float(value)
      return nil unless value.is_a?(Numeric)
      return nil unless value.positive?

      value.to_f
    end

    def parse_timestamp(raw)
      return Time.current if raw.blank? || raw.to_i.zero?

      Time.zone.at(raw.to_i)
    end

    def failure(code)
      blank = Range.new(low: nil, high: nil, current: nil)
      Result.new(ok: false, price: nil, as_of: nil, eps_ttm: nil, pe: blank, forward_pe: blank,
                 peer_low: nil, peer_high: nil, peer_sample: 0,
                 eps_estimate: blank_estimate, eps_estimate_next: blank_estimate, error_code: code)
    end
  end
end
