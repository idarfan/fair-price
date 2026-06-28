# frozen_string_literal: true

class ScrapeLeapsJob < ApplicationJob
  def perform(symbol, job_id)
    result = BarchartScraperService.new(symbol).fetch_leaps
    errors = Array(result[:errors])
    result_status = case result[:status]
    when "barchart_session_expired" then "session_expired"
    when "partial_error"            then "partial_error"
    when "cached", "success"        then "success"
    else "error"
    end
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: result_status, errors: errors },
      expires_in: 30.minutes
    )
    # Write errors by symbol so controller can read them on redirect without job_id
    Rails.cache.write("leaps_last_errors_#{symbol}", errors, expires_in: 30.minutes) if errors.any?
  rescue => e
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: "error", errors: [ e.message.first(200) ] },
      expires_in: 30.minutes
    )
  end
end
