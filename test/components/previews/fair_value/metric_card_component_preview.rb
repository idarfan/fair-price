# frozen_string_literal: true

# @label Metric Card
class FairValue::MetricCardComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Currency format
  # @param label text
  # @param value number
  # @param currency select [USD, TWD]
  # @param decimals number
  def currency(label: "目前股價", value: 213.32, currency: "USD", decimals: 2)
    render FairValue::MetricCardComponent.new(label:, value:, format: :currency, currency:, decimals:)
  end

  # @label Percent format
  # @param label text
  # @param value number "Decimal form (0.15 = 15%)"
  # @param decimals number
  def percent(label: "ROE", value: 0.1567, decimals: 1)
    render FairValue::MetricCardComponent.new(label:, value:, format: :percent, decimals:)
  end

  # @label Large number (billions)
  # @param label text
  # @param value number
  def large(label: "自由現金流", value: 108_807_000_000.0)
    render FairValue::MetricCardComponent.new(label:, value:, format: :large)
  end

  # @label With icon and caption
  # @param label text
  # @param value number
  # @param icon text "Emoji icon"
  # @param caption text "Caption below value"
  def with_extras(label: "EPS (TTM)", value: 6.43, icon: "💰", caption: "過去12個月")
    render FairValue::MetricCardComponent.new(label:, value:, format: :currency, icon:, caption:)
  end

  # @label Nil / missing value
  def missing_value
    render FairValue::MetricCardComponent.new(label: "Forward EPS", value: nil, format: :currency)
  end

  # @label Positive highlight
  def positive_highlight
    render FairValue::MetricCardComponent.new(label: "營收成長(YoY)", value: 0.054, format: :percent, highlight: :positive)
  end

  # @label Negative highlight
  def negative_highlight
    render FairValue::MetricCardComponent.new(label: "EPS成長(YoY)", value: -0.032, format: :percent, highlight: :negative)
  end
end
