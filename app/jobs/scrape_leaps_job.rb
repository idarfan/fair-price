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
  rescue => e
    err_msg = e.message.first(200)
    Rails.cache.write(
      "leaps_job_#{job_id}",
      { status: "error", errors: [ err_msg ] },
      expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
    )
    Rails.cache.write("leaps_last_errors_#{symbol}", [ err_msg ], expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW)
  end
end
