# frozen_string_literal: true

# @label Risk Alert
class DailyMomentum::RiskAlertComponentPreview < Lookbook::Preview
  SAMPLE_EARNINGS = [
    { symbol: "NVDA", date: "2025-05-21" },
    { symbol: "TSLA", date: "2025-05-22" }
  ].freeze

  # @label Low risk
  def low
    render DailyMomentum::RiskAlertComponent.new(vix: 14.2, level: :low, earnings: [], max_position: "10% 單筆上限")
  end

  # @label Medium risk with earnings
  def medium
    render DailyMomentum::RiskAlertComponent.new(vix: 19.5, level: :medium, earnings: SAMPLE_EARNINGS, max_position: "5% 單筆上限")
  end

  # @label High risk
  def high
    render DailyMomentum::RiskAlertComponent.new(vix: 31.0, level: :high, earnings: SAMPLE_EARNINGS, max_position: "2% 單筆上限，建議空倉觀望")
  end
end
