# frozen_string_literal: true

class IvStatsService
  PERIOD_1Y = 252
  PERIOD_2Y = 504

  QUALITY_THRESHOLDS = {
    insufficient: 0...30,
    limited:      30...180,
    good:         180...365,
    excellent:    365..Float::INFINITY
  }.freeze

  Result = Data.define(
    :ivr_1y, :ivp_1y,
    :ivr_2y, :ivp_2y,
    :available_days, :data_quality
  )

  def self.calculate(ticker, current_iv)
    new(ticker, current_iv.to_f).calculate
  end

  def initialize(ticker, current_iv)
    @ticker     = ticker.to_s.upcase.strip
    @current_iv = current_iv
  end

  def calculate
    snapshots = IvDailySnapshot.for_ticker(@ticker).ordered.pluck(:atm_iv).map(&:to_f)
    available = snapshots.size

    quality = QUALITY_THRESHOLDS.find { |_, range| range.cover?(available) }&.first || :insufficient

    if available < 30
      return Result.new(
        ivr_1y: nil, ivp_1y: nil,
        ivr_2y: nil, ivp_2y: nil,
        available_days: available,
        data_quality: quality.to_s
      )
    end

    ivr_1y, ivp_1y = period_stats(snapshots, PERIOD_1Y)
    ivr_2y, ivp_2y = period_stats(snapshots, PERIOD_2Y)

    Result.new(
      ivr_1y: ivr_1y, ivp_1y: ivp_1y,
      ivr_2y: ivr_2y, ivp_2y: ivp_2y,
      available_days: available,
      data_quality: quality.to_s
    )
  end

  private

  def period_stats(all_snapshots, period)
    window = all_snapshots.last(period)
    return [nil, nil] if window.size < 30

    min   = window.min
    max   = window.max
    total = window.size

    ivr = max == min ? 0.0 : ((@current_iv - min) / (max - min) * 100).round(2)
    ivp = (window.count { |v| v < @current_iv }.to_f / total * 100).round(2)

    [ivr, ivp]
  end
end
