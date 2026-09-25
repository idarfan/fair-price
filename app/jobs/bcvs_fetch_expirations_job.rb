# frozen_string_literal: true

class BcvsFetchExpirationsJob < ApplicationJob
  def perform(symbol, job_id)
    # 與 LEAPS 垂直價差共用同一個標的鎖：同時在抓時等前一次寫完快取再讀
    result = SymbolScrapeLock.with(symbol) { BarchartScraperService.new(symbol).fetch_bcvs_expirations }

    result_status = case result[:status]
    when "barchart_session_expired" then "session_expired"
    when "no_candidates"            then "no_candidates"
    when "success"                  then "success"
    else "error"
    end

    Rails.cache.write(
      "bcvs_job_#{job_id}",
      { status: result_status, errors: Array(result[:errors]) },
      expires_in: 5.minutes
    )
  rescue => e
    Rails.cache.write(
      "bcvs_job_#{job_id}",
      { status: "error", errors: [ e.message.first(200) ] },
      expires_in: 5.minutes
    )
  end
end
