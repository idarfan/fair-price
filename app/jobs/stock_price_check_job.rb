# frozen_string_literal: true

# Background job that checks active price alerts against live quotes.
# Schedule via cron (e.g., every minute during market hours):
#   rake stock_alerts:check
# or enqueue manually: StockPriceCheckJob.perform_later
class StockPriceCheckJob < ApplicationJob
  queue_as :default

  def perform
    StockPriceChecker.new.run
  rescue StandardError => e
    Rails.logger.error("[StockPriceCheckJob] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    raise
  end
end
