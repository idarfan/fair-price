# frozen_string_literal: true

class ScrapeLeapsJob < ApplicationJob
  def perform(symbol, job_id)
    result = BarchartScraperService.new(symbol).fetch_leaps
    result_status = case result[:status]
    when "barchart_session_expired" then "session_expired"
    when "cached", "success", "partial_error" then "success"
    else "error"
    end
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: result_status, errors: Array(result[:errors]) },
      expires_in: 30.minutes
    )
  rescue => e
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: "error", errors: [ e.message.first(200) ] },
      expires_in: 30.minutes
    )
  end
end
