# frozen_string_literal: true

class TechnicalDashboardAnalyzeJob < ApplicationJob
  queue_as :default

  def perform(symbol, date_str, job_id)
    cache_key = "td_job_#{job_id}"

    scrape = BarchartScraperService.new(symbol).call

    result_status = case scrape[:status]
    when "barchart_session_expired" then "session_expired"
    when "success", "partial_error"  then "success"
    else                                  "error"
    end

    Rails.cache.write(cache_key, {
      status: result_status,
      errors: Array(scrape[:errors])
    }, expires_in: 30.minutes)
  rescue => e
    Rails.cache.write("td_job_#{job_id}", {
      status: "error",
      errors: [ e.message.first(200) ]
    }, expires_in: 30.minutes)
  end
end
