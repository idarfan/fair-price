# frozen_string_literal: true

class Api::V1::ChartsController < Api::V1::BaseController
  include Charts::TechnicalIndicators

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

    sr = if intraday
           daily = YahooFinanceService.new.chart(symbol, range: "1mo", interval: "1d")
           calc_support_resistance(daily[:closes])
    else
           calc_support_resistance(closes)
    end

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
end
