# frozen_string_literal: true

class FairValue::PriceRangeComponent < ApplicationComponent
  # @param low [Float, nil] 52-week low price
  # @param high [Float, nil] 52-week high price
  # @param current [Float, nil] Current price
  # @param currency [String] Currency code
  # @param bar_height [String] Tailwind height class for the bar
  # @param show_labels [Boolean] Show low/high labels and current price label
  # @param show_percent_from_low [Boolean] Show how far current is above the low
  def initialize(
    low:,
    high:,
    current:,
    currency: "USD",
    bar_height: "h-3",
    show_labels: true,
    show_percent_from_low: true
  )
    @low                  = low
    @high                 = high
    @current              = current
    @currency             = currency
    @bar_height           = bar_height
    @show_labels          = show_labels
    @show_percent_from_low = show_percent_from_low
  end

  def view_template
    return if @low.nil? || @high.nil? || @current.nil?
    return if @high <= @low

    div(class: "space-y-2") do
      if @show_labels
        div(class: "flex justify-between text-xs text-gray-500") do
          span { plain("52週低") }
          span(class: "font-medium text-gray-700") { plain("目前價格") }
          span { plain("52週高") }
        end
      end

      div(class: "relative #{@bar_height} bg-gray-200 rounded-full overflow-hidden") do
        # Fill bar: from low to current
        div(
          class: "absolute left-0 top-0 #{@bar_height} rounded-full #{fill_color}",
          style: "width: #{fill_percent}%"
        )
        # Current price marker
        div(
          class: "absolute top-0 bottom-0 w-0.5 bg-gray-800",
          style: "left: calc(#{position_percent}% - 1px)"
        )
      end

      if @show_labels
        div(class: "flex justify-between text-xs font-medium") do
          span(class: "text-gray-600") { plain(fmt_currency(@low, currency: @currency)) }
          span(class: "#{current_label_color} text-center") do
            plain(fmt_currency(@current, currency: @currency))
            if @show_percent_from_low
              pct = ((@current - @low) / (@high - @low) * 100).round(0)
              plain(" (#{pct}%)")
            end
          end
          span(class: "text-gray-600") { plain(fmt_currency(@high, currency: @currency)) }
        end
      end
    end
  end

  private

  def position_percent
    [(@current - @low) / (@high - @low) * 100, 0].max.clamp(0, 100).round(1)
  end

  def fill_percent
    position_percent
  end

  def fill_color
    pos = position_percent
    if    pos >= 75 then "bg-red-400"
    elsif pos >= 50 then "bg-yellow-400"
    else                 "bg-green-400"
    end
  end

  def current_label_color
    pos = position_percent
    if    pos >= 75 then "text-red-600"
    elsif pos >= 50 then "text-yellow-600"
    else                 "text-green-600"
    end
  end
end
