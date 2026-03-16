# frozen_string_literal: true

class FairValue::StockHeaderComponent < ApplicationComponent
  # @param symbol [String] Ticker symbol (e.g. "AAPL")
  # @param name [String] Company name
  # @param sector [String, nil] Sector classification
  # @param industry [String, nil] Industry label
  # @param exchange [String, nil] Exchange name
  # @param currency [String] Currency code
  # @param current_price [Float, nil] Current price
  # @param fifty_two_week_low [Float, nil] 52-week low
  # @param fifty_two_week_high [Float, nil] 52-week high
  # @param show_52_week_range [Boolean] Render the 52-week range bar
  # @param compact [Boolean] Render a compact single-row version
  def initialize(
    symbol:,
    name:,
    sector: nil,
    industry: nil,
    exchange: nil,
    currency: "USD",
    current_price: nil,
    fifty_two_week_low: nil,
    fifty_two_week_high: nil,
    show_52_week_range: true,
    compact: false
  )
    @symbol              = symbol
    @name                = name
    @sector              = sector
    @industry            = industry
    @exchange            = exchange
    @currency            = currency
    @current_price       = current_price
    @fifty_two_week_low  = fifty_two_week_low
    @fifty_two_week_high = fifty_two_week_high
    @show_52_week_range  = show_52_week_range
    @compact             = compact
  end

  def view_template
    div(class: "bg-white rounded-2xl shadow-sm border border-gray-100 p-6") do
      div(class: "flex flex-col sm:flex-row sm:items-start gap-4") do
        # Left: symbol + name
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-3 flex-wrap") do
            span(class: "text-3xl font-black text-blue-700 tracking-tight") { plain(@symbol) }
            if @exchange
              span(class: "text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded font-medium") { plain(@exchange) }
            end
          end
          p(class: "mt-1 text-lg font-medium text-gray-800 truncate") { plain(@name) }
          div(class: "mt-2 flex gap-2 flex-wrap") do
            if @sector
              span(class: "text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full") { plain(@sector) }
            end
            if @industry && @industry != @sector
              span(class: "text-xs bg-gray-50 text-gray-500 px-2 py-0.5 rounded-full border border-gray-200") { plain(@industry) }
            end
          end
        end
        # Right: price
        if @current_price
          div(class: "text-right") do
            p(class: "text-xs text-gray-400 mb-1") { plain("目前股價") }
            p(class: "text-4xl font-black text-gray-900 tabular-nums") do
              plain(fmt_currency(@current_price, currency: @currency))
            end
          end
        end
      end
      if @show_52_week_range && @fifty_two_week_low && @fifty_two_week_high
        div(class: "mt-5 border-t border-gray-100 pt-4") do
          p(class: "text-xs text-gray-500 mb-2 font-medium") { plain("52週價格區間") }
          render FairValue::PriceRangeComponent.new(
            low:      @fifty_two_week_low,
            high:     @fifty_two_week_high,
            current:  @current_price,
            currency: @currency
          )
        end
      end
    end
  end
end
