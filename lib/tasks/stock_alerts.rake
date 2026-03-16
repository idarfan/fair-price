# frozen_string_literal: true

namespace :stock_alerts do
  desc "Run stock price check (enqueue StockPriceCheckJob)"
  task check: :environment do
    StockPriceChecker.new.run
    puts "[stock_alerts:check] Done"
  rescue StandardError => e
    warn "[stock_alerts:check] Error: #{e.message}"
    exit 1
  end
end
