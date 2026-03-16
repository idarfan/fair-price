# frozen_string_literal: true

# @label Fair Value Summary
class FairValue::FairValueSummaryComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Undervalued
  # @param fair_value_low number
  # @param fair_value_high number
  # @param current_price number
  # @param show_details toggle
  def undervalued(fair_value_low: 197.83, fair_value_high: 398.70, current_price: 213.32, show_details: true)
    render FairValue::FairValueSummaryComponent.new(
      fair_value_low:,
      fair_value_high:,
      current_price:,
      stock_type: "一般股",
      growth_rate: 0.089,
      growth_rate_note: "盈餘成長(YoY)、營收成長",
      judgment: "🟢 合理",
      show_details:
    )
  end

  # @label Overvalued
  # @param current_price number
  def overvalued(current_price: 280.0)
    render FairValue::FairValueSummaryComponent.new(
      fair_value_low: 150.0,
      fair_value_high: 220.0,
      current_price:,
      stock_type: "一般股",
      growth_rate: 0.05,
      judgment: "🔴 明顯高估"
    )
  end

  # @label Financial stock
  def financial_stock
    render FairValue::FairValueSummaryComponent.new(
      fair_value_low: 38.0,
      fair_value_high: 52.5,
      current_price: 45.0,
      stock_type: "金融股",
      growth_rate: 0.04,
      judgment: "🟢 合理"
    )
  end

  # @label Insufficient data
  def insufficient_data
    render FairValue::FairValueSummaryComponent.new(
      fair_value_low: nil,
      fair_value_high: nil,
      current_price: 100.0,
      stock_type: "虧損成長股",
      judgment: "⚪ 資料不足"
    )
  end
end
