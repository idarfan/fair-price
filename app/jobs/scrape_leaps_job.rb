# frozen_string_literal: true

class ScrapeLeapsJob < ApplicationJob
  # 同代號＋同履約價同時只跑一個抓取，後來的人共用同一個 job_id（前端只是輪詢
  # /leaps/status?job_id=，拿到同一個 id 就等同一份結果）。並行化計畫 S3。
  #
  # 登記記下持有程序（PROCESS_TOKEN）：server 重啟砍掉 Async job 後舊登記作廢。
  # 查詢與登記用 Mutex 包成原子操作——前提同 ScrapePriceContextJob::LOCK_MUTEX
  # （Puma single mode＋Async adapter；改 cluster mode 要換跨程序的做法）。
  # TTL 只用來清垃圾：job 結束時一定會取消登記（perform 的 ensure）。
  INFLIGHT_TTL   = 30.minutes
  INFLIGHT_MUTEX = Mutex.new

  def self.inflight_key(symbol, user_strike)
    "leaps_inflight_#{symbol.to_s.upcase}_#{user_strike.nil? ? 'auto' : user_strike.to_f}"
  end

  # 已有本程序進行中的同一抓取就回它的 job_id；否則產生新 job_id、登記，
  # 交給區塊去寫初始狀態並排程。區塊丟例外時取消登記再往外拋。
  def self.join_or_start(symbol, user_strike)
    key = inflight_key(symbol, user_strike)
    INFLIGHT_MUTEX.synchronize do
      current = Rails.cache.read(key)
      return current[:job_id] if current.is_a?(Hash) && current[:owner] == PROCESS_TOKEN

      job_id = SecureRandom.hex(8)
      Rails.cache.write(key, { job_id: job_id, owner: PROCESS_TOKEN }, expires_in: INFLIGHT_TTL)
      begin
        yield job_id
      rescue
        Rails.cache.delete(key)
        raise
      end
      job_id
    end
  end

  # 只取消自己的登記：舊 job 晚結束時，不能把新一輪的登記清掉。
  def self.finish_inflight(symbol, user_strike, job_id)
    key = inflight_key(symbol, user_strike)
    INFLIGHT_MUTEX.synchronize do
      current = Rails.cache.read(key)
      Rails.cache.delete(key) if current.is_a?(Hash) && current[:job_id] == job_id
    end
  end

  def perform(symbol, job_id, user_strike: nil)
    scrape_and_record(symbol, job_id, user_strike)
  ensure
    self.class.finish_inflight(symbol, user_strike, job_id)
  end

  private

  def scrape_and_record(symbol, job_id, user_strike)
    result = BarchartScraperService.new(symbol).fetch_leaps(user_strike: user_strike)
    errors = Array(result[:errors])
    result_status = case result[:status]
    when "barchart_session_expired" then "session_expired"
    when "partial_error"            then "partial_error"
    when "no_candidates"            then "no_candidates"
    when "invalid_strike"           then "invalid_strike"
    when "cached", "success"        then "success"
    else "error"
    end

    # 先抓 Short Call 再寫狀態：前端一看到狀態就跳轉，先寫的話頁面會比 Short Call
    # 早 1.5 分鐘出現，PMCC 區塊顯示「尚無 Short Call 資料」（2026-09-25 ORCL）。
    fetch_pmcc_short_calls_isolated(symbol)

    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: result_status, errors: errors },
      expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
    )
    # Write errors by symbol so controller can read them on redirect without job_id
    Rails.cache.write("leaps_last_errors_#{symbol}", errors, expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW) if errors.any?
  rescue => e
    err_msg = e.message.first(200)
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: "error", errors: [ err_msg ] },
      expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
    )
    Rails.cache.write("leaps_last_errors_#{symbol}", [ err_msg ], expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW)
  end

  # PMCC v3 §1/§8 鐵律：Short Call 抓取失敗不可讓 LEAPS 查詢的 job 狀態變 error。
  # 獨立 begin/rescue——例外只記錄，絕不往外拋到 perform 的頂層 rescue（那個
  # rescue 會把已經寫好的 leaps_job_#{job_id} 成功狀態覆蓋成 "error"）。
  def fetch_pmcc_short_calls_isolated(symbol)
    BarchartScraperService.new(symbol).fetch_pmcc_short_calls
  rescue => e
    Rails.logger.warn("[pmcc] fetch_pmcc_short_calls failed (non-fatal, LEAPS query unaffected): #{e.message}")
  end
end
