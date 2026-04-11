# frozen_string_literal: true

module Charts
  # Pure calculation methods for technical indicators.
  # Include in controllers or call via Charts::TechnicalIndicators.method_name.
  module TechnicalIndicators
    # Returns SMA array aligned with closes. Nil for the first period-1 entries.
    def calc_ma(closes, period)
      closes.each_with_index.map do |_, i|
        next nil if i < period - 1

        closes[(i - period + 1)..i].sum.to_f / period
      end
    end

    # Returns RSI array using Wilder's smoothing. Nil until enough data.
    def calc_rsi(closes, period)
      result  = Array.new(closes.length, nil)
      changes = closes.each_cons(2).map { |a, b| b - a }
      return result if changes.length < period

      first = changes[0, period]
      avg_g = first.select { |c| c > 0 }.sum.to_f / period
      avg_l = first.select { |c| c < 0 }.sum.abs.to_f / period
      result[period] = avg_l.zero? ? 100.0 : (100.0 - 100.0 / (1.0 + avg_g / avg_l)).round(1)

      (period...changes.length).each do |i|
        g = changes[i] > 0 ? changes[i].to_f : 0.0
        l = changes[i] < 0 ? changes[i].abs.to_f : 0.0
        avg_g = (avg_g * (period - 1) + g) / period
        avg_l = (avg_l * (period - 1) + l) / period
        result[i + 1] = avg_l.zero? ? 100.0 : (100.0 - 100.0 / (1.0 + avg_g / avg_l)).round(1)
      end

      result
    end

    # Detects pivot-based support/resistance levels. Returns { support:, resistance: }.
    def calc_support_resistance(closes)
      return { support: [], resistance: [] } if closes.length < 5

      pivot_highs = []
      pivot_lows  = []

      (2...(closes.length - 2)).each do |i|
        window = closes[(i - 2)..(i + 2)]
        pivot_highs << closes[i] if closes[i] == window.max
        pivot_lows  << closes[i] if closes[i] == window.min
      end

      last_close = closes.last
      resistance = cluster_levels(pivot_highs).select { |l| l > last_close }
      support    = cluster_levels(pivot_lows).select  { |l| l < last_close }

      { support: support.last(2), resistance: resistance.first(2) }
    end

    def rsi_label(v)
      return "—"      if v.nil?
      return "強力超買" if v >= 80
      return "超買"    if v >= 70
      return "偏多"    if v >= 50
      return "偏空"    if v >= 30
      return "超賣"    if v >= 20

      "強力超賣"
    end

    def vol_label(ratio)
      return "爆量" if ratio >= 200
      return "放量" if ratio >= 130
      return "縮量" if ratio <= 60

      "正常量"
    end

    private

    # Clusters nearby price levels within 1.5% tolerance; returns medians of top clusters.
    def cluster_levels(levels)
      sorted = levels.sort
      groups = []
      sorted.each do |lvl|
        if groups.last && (lvl - groups.last.last).abs / groups.last.last <= 0.015
          groups.last << lvl
        else
          groups << [ lvl ]
        end
      end
      groups
        .sort_by { |g| -g.length }
        .first(4)
        .map { |g| g.sort[g.length / 2].round(2) }
        .sort
    end
  end
end
