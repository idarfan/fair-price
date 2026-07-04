# frozen_string_literal: true

class StrikeChainSnapshot < ApplicationRecord
  validates :symbol,     presence: true
  validates :strikes,    presence: true
  validates :scraped_at, presence: true

  TOLERANCE_FALLBACK_RATIO = 0.10

  def min_strike = strikes.min
  def max_strike = strikes.max

  def tolerance
    return max_strike * TOLERANCE_FALLBACK_RATIO if strikes.size <= 1

    spacings = strikes.each_cons(2).map { |a, b| b - a }
    spacings.sum / spacings.size
  end

  def valid_strike?(user_strike)
    s = user_strike.to_f
    s >= (min_strike - tolerance) && s <= (max_strike + tolerance)
  end

  def invalid_message(symbol, user_strike)
    p = spot_price ? "$#{format('%.2f', spot_price)}" : "不明"
    "Strike #{user_strike} 不在 #{symbol} 的履約價範圍" \
      "（實際範圍 $#{format('%.2f', min_strike)}–$#{format('%.2f', max_strike)}，現價 #{p}），請重新輸入"
  end
end
