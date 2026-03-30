# frozen_string_literal: true

class Api::V1::ChartsController < ApplicationController
  RANGE_MAP = {
    "1m" => "1mo",
    "3m" => "3mo",
    "6m" => "6mo",
    "1y" => "1y"
  }.freeze

  def show
    symbol    = params[:symbol].upcase
    api_range = RANGE_MAP.fetch(params[:range].to_s, "1mo")

    raw = YahooFinanceService.new.chart(symbol, range: api_range)
    return render json: { error: "no data" }, status: :not_found if raw[:closes].empty?

    closes     = raw[:closes]
    volumes    = raw[:volumes]
    timestamps = raw[:timestamps]

    labels = build_labels(timestamps, closes.length)
    ma20   = calc_ma(closes, 20)
    ma50   = calc_ma(closes, 50)
    rsi14  = calc_rsi(closes, 14)
    rsi7   = calc_rsi(closes, 7)
    avg_vol = volumes.sum.to_f / volumes.length

    data = closes.each_with_index.map do |close, i|
      {
        date:    labels[i],
        close:   close.round(2),
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

    render json: { symbol: symbol, range: params[:range], data: data, stats: stats }
  end

  private

  def build_labels(timestamps, count)
    return timestamps.map { |ts| Time.at(ts).strftime("%-m/%-d") } if timestamps.length == count

    count.times.map { |i| (Date.today - (count - 1 - i)).strftime("%-m/%-d") }
  end

  def calc_ma(closes, period)
    closes.each_with_index.map do |_, i|
      next nil if i < period - 1

      closes[(i - period + 1)..i].sum.to_f / period
    end
  end

  def calc_rsi(closes, period)
    closes.each_with_index.map do |_, i|
      next nil if i < period

      changes = closes[(i - period + 1)..i].each_cons(2).map { |a, b| b - a }
      gains   = changes.select { |c| c > 0 }.sum.to_f / period
      losses  = changes.select { |c| c < 0 }.sum.abs.to_f / period
      losses.zero? ? 100.0 : (100.0 - 100.0 / (1.0 + gains / losses)).round(1)
    end
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

  def vol_label(ratio)
    return "爆量" if ratio >= 200
    return "放量" if ratio >= 130
    return "縮量" if ratio <= 60

    "正常量"
  end
end
