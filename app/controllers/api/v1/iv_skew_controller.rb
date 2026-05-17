# frozen_string_literal: true

class Api::V1::IvSkewController < Api::V1::BaseController
  DAYS_MAP = {
    "30d"  => 30,
    "90d"  => 90,
    "180d" => 180,
    "1y"   => 365
  }.freeze

  def history
    ticker = params[:ticker].to_s.upcase.strip
    return render json: { error: "Invalid ticker" }, status: :unprocessable_entity unless ticker.match?(/\A[A-Z0-9.\-]{1,10}\z/)

    days = DAYS_MAP.fetch(params[:range].to_s, 90)
    since = days.days.ago.to_date

    skew_rows = SkewRankDaily
      .for_ticker(ticker)
      .where("snapshot_date >= ?", since)
      .ordered
      .select(:snapshot_date, :put_iv_025, :call_iv_025, :skew_pts, :skew_rank)

    price_rows = IvDailySnapshot
      .where(ticker: ticker)
      .where("snapshot_date >= ?", since)
      .order(:snapshot_date)
      .pluck(:snapshot_date, :current_price)
      .to_h

    data = skew_rows.map do |r|
      {
        date:       r.snapshot_date.strftime("%Y-%m-%d"),
        put_iv:     r.put_iv_025&.to_f&.round(4),
        call_iv:    r.call_iv_025&.to_f&.round(4),
        skew_pts:   r.skew_pts&.to_f&.round(4),
        skew_rank:  r.skew_rank&.to_f&.round(1),
        price:      price_rows[r.snapshot_date]&.to_f&.round(2)
      }
    end

    skew_values = data.filter_map { |d| d[:skew_pts] }.sort
    p75 = skew_values.empty? ? nil : percentile(skew_values, 75).round(4)

    render json: { ticker: ticker, range: params[:range] || "90d", p75_skew: p75, data: data }
  end

  private

  def percentile(sorted, pct)
    return sorted.first if sorted.size == 1
    rank = (pct / 100.0) * (sorted.size - 1)
    lower = sorted[rank.floor]
    upper = sorted[rank.ceil]
    lower + (upper - lower) * (rank - rank.floor)
  end
end
