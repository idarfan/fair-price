# frozen_string_literal: true

# Checks open margin positions and sends Telegram reminders
# when the next charge date is TARGET_DAYS_BEFORE days away.
# Run daily via: bundle exec rake margin:interest_reminder
class MarginInterestReminderService
  TARGET_DAYS_BEFORE = 2

  def call
    positions = MarginPosition.open_positions
    upcoming = positions.select { |p|
      MarginInterestService.next_charge_date(p) == Date.current + TARGET_DAYS_BEFORE
    }
    return if upcoming.empty?

    telegram = TelegramService.new
    upcoming.each { |p| telegram.send_message(build_message(p)) }
  end

  private

  def build_message(position)
    charge_date   = MarginInterestService.next_charge_date(position)
    period_amount = MarginInterestService.current_period_interest(position)
    balance       = position.balance
    rate          = MarginInterestService.rate_for(balance)

    <<~MSG.strip
      💰 <b>融資支付利息提醒通知</b>

      <b>#{position.symbol}</b> 將於 <b>#{charge_date}</b> 收息（後天）
      融資餘額：$#{sprintf('%.2f', balance)}
      年利率：#{sprintf('%.2f', rate * 100)}%
      本期預估利息：<b>$#{sprintf('%.2f', period_amount)}</b>

      請確保帳戶有足夠現金！
    MSG
  end
end
