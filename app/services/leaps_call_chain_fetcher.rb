# frozen_string_literal: true

# LEAPS 垂直價差的 call chain 來源（leaps-call-spread-spec P1）。
#
# 回傳標的每一個 LEAPS 到期日（DTE ≥ LeapsRankingService::MIN_DTE）的全部 call：
# 履約價、bid、ask、last、delta（皆 BigDecimal）與抓取時間。
#
# - 快取：垂直價差自己的 leaps_spread_quotes 與到期日清單（LeapsSpreadCache），
#   與 bcvs 完全分開（使用者裁示）；以 (ticker, expiry) 為單位判斷 30 分鐘，
#   只抓過期或沒有快取的到期日。sidecar 也是垂直價差專用的兩支腳本。
# - 停滯判定：每個階段（到期日清單、每個到期日的 chain）各給 STALL_TIMEOUT 秒，
#   有進度就繼續等，單一階段超時才判定失敗；失敗時這一輪抓到的 chain 一筆都不寫。
# - 同一標的互斥：LeapsSpreadFetchLock，後到的請求等待後直接讀前一次寫好的快取。
# - 進度寫進 Rails.cache（.progress 讀取），給 P4 的進度條輪詢。
class LeapsCallChainFetcher
  # P0 第 10 步實測：單一到期日最慢 7.61 秒 → max(30, ceil(7.61 × 3)) = 30。
  # 後端與 E2E 都讀這個常數，不要在別處寫死秒數。
  STALL_TIMEOUT = 30
  PROGRESS_TTL = 10.minutes

  class Stalled < StandardError
    def initialize(stage, seconds)
      super("#{stage} 超過 #{seconds} 秒沒有回應")
    end
  end

  class FetchFailed < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.normalize(ticker) = ticker.to_s.strip.upcase
  def self.progress_key(symbol) = "leaps_call_chain_progress:#{normalize(symbol)}"
  def self.progress(symbol) = Rails.cache.read(progress_key(symbol))

  def self.stage_label(kind, expiry)
    kind == :expirations ? "讀取到期日清單" : "讀取 #{expiry.to_s[0, 10]} chain"
  end

  def initialize(ticker, runner: SidecarRunner.new)
    @symbol = self.class.normalize(ticker)
    @runner = runner
  end

  # only_expiry：選單切換到某個到期日時只刷新那一個（其他到期日不重抓）。
  def call(only_expiry: nil)
    LeapsSpreadFetchLock.with(@symbol) do
      leaps = leaps_expirations(allow_stale: only_expiry.present?)
      targets = (only_expiry ? [ only_expiry ] & leaps : leaps)
                  .reject { |expiry| LeapsSpreadCache.fresh_chain?(@symbol, expiry) }
      persist!(fetch_chains(targets))
      write_progress(state: "done", done: targets.size, total: targets.size)
      build_result(leaps)
    end
  rescue Stalled, FetchFailed => e
    code = e.is_a?(Stalled) ? :stalled : e.code
    write_progress(state: "error", message: e.message)
    { status: :error, code: code, symbol: @symbol, message: e.message }
  end

  private

  def leaps_expirations(allow_stale:)
    cached = LeapsSpreadCache.read_expirations(@symbol)
    list = if cached && (allow_stale || LeapsSpreadCache.fresh_expirations?(@symbol))
      cached
    else
      fetch_expirations
    end

    leaps = list.select { |expiry| leaps?(expiry) }
    raise FetchFailed.new(:no_leaps, "#{@symbol} 沒有適合的 LEAPS 標的") if leaps.empty?

    leaps
  end

  def fetch_expirations
    write_progress(state: "running", stage: self.class.stage_label(:expirations, nil), done: 0, total: nil)
    data = @runner.call(:expirations, @symbol, timeout: STALL_TIMEOUT)

    case data["status"]
    when "success"
      LeapsSpreadCache.write_expirations!(@symbol, data["expirations"])
      Array(data["expirations"])
    when "symbol_not_found" then raise FetchFailed.new(:symbol_not_found, "查無股票代號 #{@symbol}")
    when "no_options"       then raise FetchFailed.new(:no_leaps, "#{@symbol} 沒有適合的 LEAPS 標的")
    else raise FetchFailed.new(:fetch_failed, failure_reason("讀取到期日清單", data))
    end
  end

  def fetch_chains(expiries)
    expiries.each_with_index.map do |expiry, index|
      stage = "#{self.class.stage_label(:chain, expiry)}（#{index + 1}/#{expiries.size}）"
      write_progress(state: "running", stage: stage, done: index, total: expiries.size)
      data = @runner.call(:chain, @symbol, expiry, timeout: STALL_TIMEOUT)
      unless data["status"] == "success"
        raise FetchFailed.new(:fetch_failed, failure_reason(self.class.stage_label(:chain, expiry), data))
      end

      { expiry: expiry, rows: data["rows"], underlying_price: data["underlying_price"] }
    end
  end

  def failure_reason(stage, data)
    detail = case data["status"]
    when "barchart_session_expired" then "Barchart 登入 Session 已過期"
    when "no_candidates"            then "頁面沒有資料"
    else data["error"].presence || "status=#{data['status']}"
    end
    "#{stage}失敗：#{detail}"
  end

  # 全部成功才寫入：停滯或失敗時不留下半套快取。
  def persist!(fetched)
    ActiveRecord::Base.transaction do
      fetched.each do |f|
        LeapsSpreadCache.replace_chain!(@symbol, f[:expiry], rows: f[:rows], underlying_price: f[:underlying_price])
      end
    end
  end

  def build_result(leaps)
    chains = leaps.filter_map do |expiry|
      chain = LeapsSpreadCache.read_chain(@symbol, expiry)
      next unless chain

      { expiry: expiry, date: expiry_date(expiry), dte: dte(expiry), fetched_at: chain[:scraped_at],
        spot: chain[:underlying_price], calls: chain[:strikes] }
    end

    { status: :ok, symbol: @symbol, spot: chains.max_by { |c| c[:fetched_at] }&.dig(:spot),
      expirations: chains.map { |c| c.except(:spot) } }
  end

  def leaps?(expiry) = dte(expiry) >= LeapsRankingService::MIN_DTE
  def expiry_date(expiry) = Date.parse(expiry.to_s[0, 10])
  def dte(expiry) = (expiry_date(expiry) - Date.current).to_i

  def write_progress(**attrs)
    key = self.class.progress_key(@symbol)
    previous = Rails.cache.read(key) || {}
    started_at = attrs[:state] == "running" && previous[:state] != "running" ? Time.current : previous[:started_at]
    Rails.cache.write(key, previous.merge(attrs, started_at: started_at, updated_at: Time.current),
                      expires_in: PROGRESS_TTL)
  end
end
