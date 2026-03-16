# frozen_string_literal: true

# Checks active price alerts against live Finnhub quotes.
# Called by StockPriceCheckJob on a recurring schedule during market hours.
class StockPriceChecker
  def initialize
    @finnhub  = FinnhubService.new
    @telegram = TelegramService.new
  end

  def run
    unless market_open?
      Rails.logger.info("[StockPriceChecker] 市場休市中，略過本次檢查")
      return
    end

    alerts = PriceAlert.active.to_a
    return if alerts.empty?

    alerts.group_by(&:symbol).each do |symbol, symbol_alerts|
      quote = @finnhub.quote(symbol)
      unless quote
        Rails.logger.warn("[StockPriceChecker] Could not fetch price for #{symbol}")
        next
      end

      current_price = quote["c"].to_f
      Rails.logger.info("[StockPriceChecker] #{symbol} current price: #{current_price}")
      symbol_alerts.each { |alert| check_alert(alert, current_price) }
    end
  end

  private

  def market_open?
    now = Time.now.in_time_zone("Eastern Time (US & Canada)")
    return false if now.saturday? || now.sunday?

    open_time  = now.change(hour: 9,  min: 30)
    close_time = now.change(hour: 16, min: 0)
    now.between?(open_time, close_time)
  end

  def check_alert(alert, current_price)
    triggered = case alert.condition
    when "above" then current_price >= alert.target_price.to_f
    when "below" then current_price <= alert.target_price.to_f
    else false
    end
    return unless triggered

    send_notification(alert, current_price)
    alert.update!(triggered_at: Time.current, active: false)
    Rails.logger.info("[StockPriceChecker] Alert ##{alert.id} triggered for #{alert.symbol}")
  end

  def send_notification(alert, current_price)
    direction      = alert.condition == "above" ? "📈" : "📉"
    condition_text = alert.condition == "above" ? "above" : "below"

    message = <<~MSG.strip
      #{direction} <b>Stock Alert Triggered!</b>

      <b>#{alert.symbol}</b> is now <b>$#{sprintf("%.2f", current_price)}</b>
      Condition: #{condition_text} $#{sprintf("%.2f", alert.target_price)}#{alert.notes.present? ? "\nNote: #{alert.notes}" : ""}
      Time: #{Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")}
    MSG

    @telegram.send_message(message)
  end
end
