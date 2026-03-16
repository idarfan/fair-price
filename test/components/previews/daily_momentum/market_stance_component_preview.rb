# frozen_string_literal: true

# @label Market Stance
class DailyMomentum::MarketStanceComponentPreview < Lookbook::Preview
  # @label Aggressive (低 VIX)
  def aggressive
    render DailyMomentum::MarketStanceComponent.new(vix: 14.2, es: 0.45, nq: 0.62, stance: :aggressive)
  end

  # @label Conservative (中 VIX)
  def conservative
    render DailyMomentum::MarketStanceComponent.new(vix: 19.5, es: -0.12, nq: 0.08, stance: :conservative)
  end

  # @label Cash (高 VIX)
  def cash
    render DailyMomentum::MarketStanceComponent.new(vix: 28.7, es: -1.5, nq: -2.1, stance: :cash)
  end

  # @label 無資料
  def no_data
    render DailyMomentum::MarketStanceComponent.new
  end
end
