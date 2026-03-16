# frozen_string_literal: true

# @label Price Range Bar
class FairValue::PriceRangeComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Near 52-week low (green zone)
  # @param low number
  # @param high number
  # @param current number
  def near_low(low: 164.08, high: 237.23, current: 180.0)
    render FairValue::PriceRangeComponent.new(low:, high:, current:)
  end

  # @label Mid range (yellow zone)
  # @param low number
  # @param high number
  # @param current number
  def mid_range(low: 164.08, high: 237.23, current: 213.32)
    render FairValue::PriceRangeComponent.new(low:, high:, current:)
  end

  # @label Near 52-week high (red zone)
  # @param low number
  # @param high number
  # @param current number
  def near_high(low: 164.08, high: 237.23, current: 230.0)
    render FairValue::PriceRangeComponent.new(low:, high:, current:)
  end

  # @label TWD currency
  def twd_currency
    render FairValue::PriceRangeComponent.new(low: 580.0, high: 1080.0, current: 820.0, currency: "TWD")
  end

  # @label Without labels
  def no_labels
    render FairValue::PriceRangeComponent.new(low: 164.08, high: 237.23, current: 213.32, show_labels: false)
  end
end
