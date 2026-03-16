# frozen_string_literal: true

class FairValue::MetricsGridComponent < ApplicationComponent
  # @param title [String, nil] Section title above grid
  # @param metrics [Array<Hash>] Array of metric hashes with :label, :value, :format, :currency, :decimals, :caption, :icon, :highlight
  # @param columns [Integer] Grid columns: 2, 3, or 4
  # @param title_size [Symbol] :sm, :md, :lg for title text size
  # @param gap_class [String] Tailwind gap class between cards
  # @param show_empty [Boolean] Whether to render cards with nil values
  def initialize(
    metrics:,
    title: nil,
    columns: 3,
    title_size: :md,
    gap_class: "gap-4",
    show_empty: true
  )
    @metrics    = metrics
    @title      = title
    @columns    = columns.clamp(2, 4)
    @title_size = title_size
    @gap_class  = gap_class
    @show_empty = show_empty
  end

  def view_template
    displayed = @show_empty ? @metrics : @metrics.reject { |m| m[:value].nil? }
    return if displayed.empty?

    div(class: "space-y-3") do
      if @title
        h3(class: "#{title_size_class} font-semibold text-gray-700") { plain(@title) }
      end
      div(class: "grid #{columns_class} #{@gap_class}") do
        displayed.each do |metric|
          render FairValue::MetricCardComponent.new(
            label:     metric[:label],
            value:     metric[:value],
            format:    metric.fetch(:format, :number),
            currency:  metric.fetch(:currency, "USD"),
            decimals:  metric.fetch(:decimals, 2),
            caption:   metric[:caption],
            icon:      metric[:icon],
            highlight: metric[:highlight],
            invert:    metric.fetch(:invert, false)
          )
        end
      end
    end
  end

  private

  def columns_class
    case @columns
    when 2 then "grid-cols-2"
    when 4 then "grid-cols-2 sm:grid-cols-4"
    else        "grid-cols-2 sm:grid-cols-3"
    end
  end

  def title_size_class
    case @title_size
    when :sm then "text-sm"
    when :lg then "text-xl"
    else          "text-base"
    end
  end
end
