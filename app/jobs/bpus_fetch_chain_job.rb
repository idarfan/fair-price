# frozen_string_literal: true

class BpusFetchChainJob < ApplicationJob
  def perform(symbol, expiration, job_id)
    result = BarchartScraperService.new(symbol).fetch_bpus_put_chain(expiration: expiration)

    result_status = case result[:status]
    when "barchart_session_expired" then "session_expired"
    when "no_candidates"            then "no_candidates"
    when "success"                  then "success"
    else "error"
    end

    Rails.cache.write(
      "bpus_job_#{job_id}",
      { status: result_status, errors: Array(result[:errors]) },
      expires_in: 5.minutes
    )
  rescue => e
    Rails.cache.write(
      "bpus_job_#{job_id}",
      { status: "error", errors: [ e.message.first(200) ] },
      expires_in: 5.minutes
    )
  end
end
