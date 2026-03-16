# frozen_string_literal: true

class FairValue::MetricCardComponent < ApplicationComponent
  # @param label [String] Card label/title
  # @param value [Numeric, nil] The value to display
  # @param format [Symbol] :currency, :percent, :large, :number, :raw
  # @param currency [String] Currency code (USD or TWD)
  # @param decimals [Integer] Decimal places for number/currency format
  # @param caption [String, nil] Small helper text below the value
  # @param icon [String, nil] Emoji or text icon shown above value
  # @param highlight [Symbol, nil] :positive/:negative/:neutral — overrides auto color
  # @param invert [Boolean] Invert color logic (higher = bad, e.g. P/E ratio)
  def initialize(
    label:,
    value:,
    format: :number,
    currency: "USD",
    decimals: 2,
    caption: nil,
    icon: nil,
    highlight: nil,
    invert: false
  )
    @label     = label
    @value     = value
    @format    = format
    @currency  = currency
    @decimals  = decimals
    @caption   = caption
    @icon      = icon
    @highlight = highlight
    @invert    = invert
  end

  def view_template
    div(class: "bg-white rounded-xl shadow-sm border border-gray-100 p-4") do
      p(class: "text-xs text-gray-500 font-medium uppercase tracking-wide") { plain(@label) }
      div(class: "mt-1 flex items-baseline gap-1") do
        if @icon
          span(class: "text-base mr-1") { plain(@icon) }
        end
        span(class: "text-xl font-bold #{value_color}") { plain(formatted_value) }
      end
      if @caption
        p(class: "text-xs text-gray-400 mt-1") { plain(@caption) }
      end
    end
  end

  private

  def formatted_value
    return "—" if @value.nil?

    case @format
    when :currency then fmt_currency(@value, currency: @currency, decimals: @decimals)
    when :percent  then fmt_percent(@value, decimals: @decimals)
    when :large    then fmt_large(@value, currency: @currency)
    when :number   then number_with_precision(@value, precision: @decimals, delimiter: ",")
    when :raw      then @value.to_s
    else @value.to_s
    end
  end

  def value_color
    return "text-gray-400" if @value.nil?
    return explicit_color(@highlight) if @highlight

    return "text-gray-900" if @format == :currency || @format == :large
    return "text-gray-900" if @format == :number || @format == :raw

    # Color logic for percent format
    if @format == :percent
      positive = @value >= 0
      positive = !positive if @invert
      positive ? "text-green-600" : "text-red-600"
    else
      "text-gray-900"
    end
  end

  def explicit_color(highlight)
    case highlight
    when :positive then "text-green-600"
    when :negative then "text-red-600"
    when :neutral  then "text-yellow-600"
    else "text-gray-900"
    end
  end
end
