# frozen_string_literal: true

class Api::V1::ChartsController < ApplicationController
  RANGE_MAP = {
    "1d" => { range: "1d",  interval: "5m"  },
    "5d" => { range: "5d",  interval: "15m" },
    "1m" => { range: "1mo", interval: "1d"  },
    "3m" => { range: "3mo", interval: "1d"  },
    "6m" => { range: "6mo", interval: "1d"  },
    "1y" => { range: "1y",  interval: "1d"  }
  }.freeze

  INTRADAY_RANGES = %w[1d 5d].freeze

  def show
    symbol = params[:symbol].to_s.upcase.strip
    return render json: { error: "Invalid symbol" }, status: :unprocessable_entity unless symbol.match?(/\A[A-Z0-9.\-]{1,10}\z/)

    range_key = params[:range].to_s
    cfg       = RANGE_MAP.fetch(range_key, RANGE_MAP["1m"])

    raw = YahooFinanceService.new.chart(symbol, range: cfg[:range], interval: cfg[:interval])
    return render json: { error: "no data" }, status: :not_found if raw[:closes].empty?

    closes     = raw[:closes]
    volumes    = raw[:volumes]
    timestamps = raw[:timestamps]
    opens      = raw[:opens]
    highs      = raw[:highs]
    lows       = raw[:lows]

    intraday = INTRADAY_RANGES.include?(range_key)
    labels      = build_labels(timestamps, closes.length, intraday: intraday, range_key: range_key)
    time_values = build_time_values(timestamps, closes.length, intraday: intraday)
    ma20   = calc_ma(closes, 20)
    ma50   = calc_ma(closes, 50)
    rsi14  = calc_rsi(closes, 14)
    rsi7   = calc_rsi(closes, 7)
    avg_vol = volumes.sum.to_f / volumes.length

    data = closes.each_with_index.map do |close, i|
      c = close.round(2)
      {
        time:    time_values[i],
        date:    labels[i],
        open:    opens[i]&.round(2) || c,
        high:    highs[i]&.round(2) || c,
        low:     lows[i]&.round(2)  || c,
        close:   c,
        volume:  volumes[i],
        ma20:    ma20[i]&.round(2),
        ma50:    ma50[i]&.round(2),
        rsi14:   rsi14[i],
        rsi7:    rsi7[i],
        avg_vol: avg_vol.round(0).to_i
      }
    end

    last_rsi14 = rsi14.compact.last
    last_rsi7  = rsi7.compact.last
    last_ma20  = ma20.compact.last
    last_close = closes.last
    today_vol  = volumes.last
    vol_ratio  = (today_vol.to_f / avg_vol * 100).round

    high = closes.max
    low  = closes.min
    pos_52w = (low - high).abs < 0.01 ? 50 : ((last_close - low) / (high - low) * 100).round

    stats = {
      rsi14:         last_rsi14,
      rsi7:          last_rsi7,
      rsi14_label:   rsi_label(last_rsi14),
      rsi7_label:    rsi_label(last_rsi7),
      ma20_price:    last_ma20&.round(2),
      ma20_dist_pct: last_ma20 ? ((last_close - last_ma20) / last_ma20 * 100).round(1) : nil,
      pos_52w_pct:   pos_52w,
      high_range:    high.round(2),
      low_range:     low.round(2),
      today_vol:     today_vol,
      avg_vol:       avg_vol.round(0).to_i,
      vol_ratio_pct: vol_ratio,
      vol_label:     vol_label(vol_ratio)
    }

    sr = intraday ? { support: [], resistance: [] } : calc_support_resistance(closes)

    render json: { symbol: symbol, range: params[:range], data: data, stats: stats, support_resistance: sr }
  end

  private

  def build_time_values(timestamps, count, intraday: false)
    if timestamps.length == count
      return timestamps if intraday  # raw Unix seconds for lightweight-charts UTCTimestamp

      timestamps.map { |ts| Time.at(ts).utc.strftime("%Y-%m-%d") }
    else
      count.times.map { |i| (Date.today - (count - 1 - i)).strftime("%Y-%m-%d") }
    end
  end

  def build_labels(timestamps, count, intraday: false, range_key: "1m")
    if timestamps.length == count
      fmt = if range_key == "1d"
              ->(ts) { Time.at(ts).in_time_zone("Eastern Time (US & Canada)").strftime("%H:%M") }
      elsif range_key == "5d"
              ->(ts) { Time.at(ts).in_time_zone("Eastern Time (US & Canada)").strftime("%-m/%-d %H:%M") }
      else
              ->(ts) { Time.at(ts).strftime("%-m/%-d") }
      end
      return timestamps.map(&fmt)
    end

    count.times.map { |i| (Date.today - (count - 1 - i)).strftime("%-m/%-d") }
  end

  def calc_ma(closes, period)
    closes.each_with_index.map do |_, i|
      next nil if i < period - 1

      closes[(i - period + 1)..i].sum.to_f / period
    end
  end

  def calc_rsi(closes, period)
    result  = Array.new(closes.length, nil)
    changes = closes.each_cons(2).map { |a, b| b - a }
    return result if changes.length < period

    # First RSI: simple average of first `period` changes
    first   = changes[0, period]
    avg_g   = first.select { |c| c > 0 }.sum.to_f / period
    avg_l   = first.select { |c| c < 0 }.sum.abs.to_f / period
    result[period] = avg_l.zero? ? 100.0 : (100.0 - 100.0 / (1.0 + avg_g / avg_l)).round(1)

    # Subsequent RSIs: Wilder's smoothing (EMA)
    (period...changes.length).each do |i|
      g = changes[i] > 0 ? changes[i].to_f : 0.0
      l = changes[i] < 0 ? changes[i].abs.to_f : 0.0
      avg_g = (avg_g * (period - 1) + g) / period
      avg_l = (avg_l * (period - 1) + l) / period
      result[i + 1] = avg_l.zero? ? 100.0 : (100.0 - 100.0 / (1.0 + avg_g / avg_l)).round(1)
    end

    result
  end

  def rsi_label(v)
    return "—" if v.nil?
    return "強力超買" if v >= 80
    return "超買" if v >= 70
    return "偏多" if v >= 50
    return "偏空" if v >= 30
    return "超賣" if v >= 20

    "強力超賣"
  end

  def calc_support_resistance(closes)
    return { support: [], resistance: [] } if closes.length < 5

    # Detect pivot highs and lows using a 2-bar window on each side
    pivot_highs = []
    pivot_lows  = []

    (2...(closes.length - 2)).each do |i|
      window = closes[(i - 2)..(i + 2)]
      pivot_highs << closes[i] if closes[i] == window.max
      pivot_lows  << closes[i] if closes[i] == window.min
    end

    # Cluster nearby levels within 1.5% of each other
    cluster = lambda do |levels|
      sorted = levels.sort
      groups = []
      sorted.each do |lvl|
        if groups.last && (lvl - groups.last.last).abs / groups.last.last <= 0.015
          groups.last << lvl
        else
          groups << [ lvl ]
        end
      end
      # Representative: median of each cluster, weighted by cluster size; take strongest 3
      groups
        .sort_by { |g| -g.length }
        .first(4)
        .map { |g| g.sort[g.length / 2].round(2) }
        .sort
    end

    last_close = closes.last

    resistance = cluster.call(pivot_highs).select { |l| l > last_close }
    support    = cluster.call(pivot_lows).select  { |l| l < last_close }

    {
      support:    support.last(2),
      resistance: resistance.first(2)
    }
  end

  def vol_label(ratio)
    return "爆量" if ratio >= 200
    return "放量" if ratio >= 130
    return "縮量" if ratio <= 60

    "正常量"
  end
end
