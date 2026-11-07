# frozen_string_literal: true

# 每日 LEAPS IV 快照（leaps-iv-environment.md P4）。由 bin/leaps_iv_snapshot（pm2 排程）呼叫。
#
# 標的：config/leaps_iv.yml 的 watchlist ∪ 最近 30 天在 /leaps 實際抓取過的 symbol（fetch_logs），
# 去重、依字母排序，最多 max_symbols 個（超出寫 log 並略過）。
# 每個標的依序（不並行）：取獨佔鎖 → LEAPS IV 曲面＋cm540（source: scheduled）→ Barchart 歷史
# （沒有任何列時 backfill，否則 latest）→ 放鎖。單一標的失敗或逾時只記 log，不中斷其他標的。
class LeapsIvSnapshotRunner
  LOG_PATH      = Rails.root.join("log/leaps_iv_snapshot.log")
  RECENT_DAYS   = 30
  QUERY_STATUSES = %w[success cached partial_error].freeze
  # 每個標的放鎖後先停這麼久再拿下一個：advisory lock 不排隊，排程放鎖後幾毫秒就重拿，
  # 每 POLL_S 秒才重試一次的互動查詢永遠搶不到，只能等整輪跑完（2026-11-06 P4 實測 AMD 等了 5 分半）。
  # 必須大於 LeapsIvCdpLock::POLL_S，正在等的查詢才一定有一次重試落在空檔裡。
  YIELD_GAP_S = 5

  def initialize(logger: ActiveSupport::Logger.new(LOG_PATH), config: LeapsIvConfig.load)
    @logger = logger
    @config = config
  end

  # 回傳 { "TSM" => :ok, ... }
  def run
    symbols = target_symbols
    @logger.info("[snapshot] 開始：#{symbols.size} 個標的 #{symbols.join(',')}")
    results = symbols.each_with_index.to_h do |sym, i|
      sleep YIELD_GAP_S if i.positive? # 讓等鎖的互動查詢先做
      [ sym, snapshot(sym) ]
    end
    @logger.info("[snapshot] 結束：#{results.map { |s, r| "#{s}=#{r}" }.join(' ')}")
    results
  end

  # bin/leaps_iv_snapshot --backfill SYMBOL
  def backfill(symbol)
    symbol = symbol.to_s.upcase
    with_lock(symbol, "backfill") do
      result = BarchartScraperService.new(symbol).fetch_barchart_iv_history(mode: "backfill", source: "scheduled")
      @logger.info("[snapshot] #{symbol} backfill：#{result[:status]} #{result[:errors].join('; ')}")
      result[:status] == "success" ? :ok : :error
    end
  rescue StandardError => e
    @logger.error("[snapshot] #{symbol} backfill 失敗：#{e.class}: #{e.message}")
    :error
  end

  def target_symbols
    max = @config.fetch("max_symbols")
    all = (Array(@config.fetch("watchlist")) + recent_query_symbols).map { |s| s.to_s.upcase }.uniq.sort
    if all.size > max
      @logger.warn("[snapshot] 標的 #{all.size} 個超過 max_symbols #{max}，略過：#{all.drop(max).join(',')}")
    end
    all.first(max)
  end

  private

  # P0 偵察「LEAPS 查詢紀錄」的查詢（fetch_logs，只算實際抓取過的狀態）
  def recent_query_symbols
    FetchLog.where(fetch_type: "leaps", status: QUERY_STATUSES)
            .where(fetched_at: RECENT_DAYS.days.ago..)
            .distinct.order(:symbol).pluck(:symbol)
  end

  def snapshot(symbol)
    with_lock(symbol, "snapshot") do
      service = BarchartScraperService.new(symbol)
      iv      = service.fetch_leaps_iv_snapshot(source: "scheduled", timeout: @config.fetch("per_symbol_timeout_sec"))
      mode    = BarchartIvHistory.for_symbol(symbol).exists? ? "latest" : "backfill"
      history = service.fetch_barchart_iv_history(mode: mode, source: "scheduled")
      @logger.info("[snapshot] #{symbol}：IV #{iv[:status]}（points=#{iv[:points].inspect} cm540=#{iv[:cm540].inspect}）" \
                   "，Barchart #{mode} #{history[:status]} #{(iv[:errors] + history[:errors]).join('; ')}".strip)
      outcome(iv[:status], history[:status])
    end
  rescue StandardError => e
    @logger.error("[snapshot] #{symbol} 失敗：#{e.class}: #{e.message}")
    :error
  end

  # 美股盤中依規則略過（pm2 start 會立即執行一次、或手動在盤中跑）不是失敗，記成 :skipped
  def outcome(*statuses)
    return :ok if statuses.all?("success")
    return :skipped if statuses.all?("skipped_regular_session")

    :error
  end

  def with_lock(symbol, what, &)
    LeapsIvCdpLock.exclusive(wait: @config.fetch("lock_wait_sec"), label: "IV 快照排程 #{symbol} #{what}",
                             logger: @logger, &)
  end
end
