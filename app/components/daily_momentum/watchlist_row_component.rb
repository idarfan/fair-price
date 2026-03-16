# frozen_string_literal: true

class DailyMomentum::WatchlistRowComponent < ApplicationComponent
  # @param symbol   [String]        Ticker symbol
  # @param name     [String, nil]   Company name
  # @param price    [Float, nil]    Current price
  # @param change   [Float, nil]    Price change amount
  # @param change_pct [Float, nil]  Change percent (0.05 = 5%)
  # @param volume   [Integer, nil]  Volume
  # @param day_high [Float, nil]    Day high
  # @param day_low  [Float, nil]    Day low
  # @param high_52w [Float, nil]    52-week high
  # @param low_52w  [Float, nil]    52-week low
  def initialize(symbol:, name: nil, price: nil, change: nil, change_pct: nil,
                 volume: nil, day_high: nil, day_low: nil, high_52w: nil, low_52w: nil)
    @symbol     = symbol
    @name       = name
    @price      = price
    @change     = change
    @change_pct = change_pct
    @volume     = volume
    @day_high   = day_high
    @day_low    = day_low
    @high_52w   = high_52w
    @low_52w    = low_52w
  end

  def view_template
    tr(class: "border-t border-gray-100 hover:bg-gray-50 transition-colors") do
      td(class: "px-4 py-3") do
        div(class: "font-mono font-bold text-gray-900") { plain(@symbol) }
        div(class: "text-xs text-gray-400 truncate max-w-28") { plain(@name || "—") }
      end
      td(class: "px-4 py-3 text-right") do
        span(class: "font-semibold text-gray-900") { plain(@price ? fmt_currency(@price) : "—") }
      end
      td(class: "px-4 py-3 text-right") do
        render_change
      end
      td(class: "px-4 py-3 text-right text-sm text-gray-500") do
        plain(@volume ? fmt_large(@volume.to_f) : "—")
      end
      td(class: "px-4 py-3 text-sm text-gray-500") do
        render_range
      end
    end
  end

  private

  def render_change
    return span(class: "text-gray-400") { plain("—") } if @change_pct.nil?

    sign  = @change_pct >= 0 ? "+" : ""
    color = change_color(@change_pct)
    div do
      div(class: "font-medium #{color}") { plain("#{sign}#{sprintf("%.2f", @change_pct * 100)}%") }
      change_sign = (@change.nil? || @change >= 0) ? "+" : ""
      div(class: "text-xs #{color} opacity-75") { plain("#{change_sign}#{fmt_currency(@change || 0)}") }
    end
  end

  def render_range
    has_day = @day_high && @day_low && @day_high > @day_low
    has_52w = @high_52w && @low_52w

    return plain("—") unless has_day || has_52w

    div(class: "min-w-44 text-xs text-gray-500 space-y-2") do
      render_range_bar("當日價格範圍", @day_low, @day_high, "bg-red-400", "text-red-500") if has_day
      render_range_bar("52週範圍", @low_52w, @high_52w, "bg-gray-400", "text-gray-500") if has_52w
    end
  end

  def render_range_bar(label, low, high, fill_class, marker_class)
    range = high - low
    pct   = range > 0 && @price ? ((@price - low) / range * 100).clamp(0, 100).round(1) : nil

    div do
      div(class: "text-center text-gray-400 mb-0.5") { plain(label) }
      div(class: "flex items-center gap-1.5") do
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(low)) }
        div(class: "relative flex-1 pb-2.5") do
          div(class: "h-1 bg-gray-200 rounded-full") do
            div(class: "h-full #{fill_class} rounded-full", style: "width:#{pct || 0}%")
          end
          if pct
            div(
              class: "absolute top-1.5 #{marker_class} leading-none",
              style: "left:calc(#{pct}% - 4px); font-size:8px"
            ) { plain("▲") }
          end
        end
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(high)) }
      end
    end
  end
end
