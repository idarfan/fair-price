# frozen_string_literal: true

class ScrapeLeapsJob < ApplicationJob
  def perform(symbol, job_id, user_strike: nil)
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
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: result_status, errors: errors },
      expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
    )
    # Write errors by symbol so controller can read them on redirect without job_id
    Rails.cache.write("leaps_last_errors_#{symbol}", errors, expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW) if errors.any?

    fetch_pmcc_short_calls_isolated(symbol)
  rescue => e
    err_msg = e.message.first(200)
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: "error", errors: [ err_msg ] },
      expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
    )
    Rails.cache.write("leaps_last_errors_#{symbol}", [ err_msg ], expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW)
  end

  private

  # PMCC v3 §1/§8 鐵律：Short Call 抓取失敗不可讓 LEAPS 查詢的 job 狀態變 error。
  # 獨立 begin/rescue——例外只記錄，絕不往外拋到 perform 的頂層 rescue（那個
  # rescue 會把已經寫好的 leaps_job_#{job_id} 成功狀態覆蓋成 "error"）。
  def fetch_pmcc_short_calls_isolated(symbol)
    BarchartScraperService.new(symbol).fetch_pmcc_short_calls
  rescue => e
    Rails.logger.warn("[pmcc] fetch_pmcc_short_calls failed (non-fatal, LEAPS query unaffected): #{e.message}")
  end
end
