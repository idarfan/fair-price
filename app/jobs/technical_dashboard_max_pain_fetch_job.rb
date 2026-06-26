# frozen_string_literal: true

class TechnicalDashboardMaxPainFetchJob < ApplicationJob
  queue_as :default

  def perform(symbol, expiration, strikes, vol_oi, job_id)
    cache_key = "td_job_#{job_id}"

    scrape = BarchartScraperService.new(symbol).fetch_max_pain(
      expiration: expiration,
      strikes:    strikes,
      volume_oi:  vol_oi
    )

    result_status = case scrape[:status]
    when "barchart_session_expired" then "session_expired"
    when "success"                  then "success"
    else                                 "error"
    end

    Rails.cache.write(cache_key, {
      status: result_status,
      errors: Array(scrape[:error])
    }, expires_in: 30.minutes)
  rescue => e
    Rails.cache.write("td_job_#{job_id}", {
      status: "error",
      errors: [ e.message.first(200) ]
    }, expires_in: 30.minutes)
  end
end
