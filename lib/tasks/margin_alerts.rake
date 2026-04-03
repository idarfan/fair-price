# frozen_string_literal: true

namespace :margin do
  desc "Check margin positions due for interest in 2 days and send Telegram reminder"
  task interest_reminder: :environment do
    MarginInterestReminderService.new.call
    puts "[margin:interest_reminder] Done at #{Time.current}"
  rescue StandardError => e
    warn "[margin:interest_reminder] Error: #{e.message}"
    exit 1
  end
end
