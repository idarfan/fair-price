# frozen_string_literal: true

# @label Metrics Grid
class FairValue::MetricsGridComponentPreview < Lookbook::Preview
  layout "component_preview"

  SAMPLE_METRICS = [
    { label: "EPS (TTM)",   value: 6.43,   format: :currency },
    { label: "Book Value",  value: 4.84,   format: :currency },
    { label: "ROE",         value: 1.569,  format: :percent,  decimals: 1 },
    { label: "股息/股",     value: 1.00,   format: :currency },
    { label: "盈餘成長",    value: 0.089,  format: :percent,  decimals: 1 },
    { label: "營收成長",    value: 0.040,  format: :percent,  decimals: 1 },
  ].freeze

  # @label 3 columns (default)
  # @param title text "Section title"
  # @param columns number "2, 3, or 4"
  def default(title: "基本財務指標", columns: 3)
    render FairValue::MetricsGridComponent.new(metrics: SAMPLE_METRICS, title:, columns: columns.to_i)
  end

  # @label 2 columns
  def two_columns
    render FairValue::MetricsGridComponent.new(metrics: SAMPLE_METRICS.first(4), columns: 2, title: "核心指標")
  end

  # @label 4 columns
  def four_columns
    render FairValue::MetricsGridComponent.new(metrics: SAMPLE_METRICS, columns: 4)
  end

  # @label With nil values hidden
  def hide_empty
    metrics = SAMPLE_METRICS + [{ label: "Forward EPS", value: nil, format: :currency }]
    render FairValue::MetricsGridComponent.new(metrics:, show_empty: false, title: "隱藏空值")
  end
end
