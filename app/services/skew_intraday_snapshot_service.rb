# frozen_string_literal: true

class SkewIntradaySnapshotService
  # ET market hours window (with small buffers)
  OPEN_H  = 9;  OPEN_M  = 25
  CLOSE_H = 16; CLOSE_M = 10

  def self.within_market_hours?
    et  = Time.current.in_time_zone("Eastern Time (US & Canada)")
    wday = et.wday
    return false unless wday.between?(1, 5) # Mon-Fri only

    open_time  = et.change(hour: OPEN_H,  min: OPEN_M,  sec: 0)
    close_time = et.change(hour: CLOSE_H, min: CLOSE_M, sec: 0)
    et >= open_time && et <= close_time
  end

  def self.fetch_and_store(ticker)
    new(ticker).call
  end

  def initialize(ticker)
    @ticker = ticker.to_s.upcase.strip
  end

  def call
    data = IvSidecarService.fetch_skew(@ticker)

    now_slot = rounded_slot(Time.current.utc)

    SkewRankIntraday.upsert(
      {
        ticker:        @ticker,
        snapshot_time: now_slot,
        put_iv_025:    data[:put_iv_025],
        call_iv_025:   data[:call_iv_025],
        skew_pts:      data[:skew_pts].to_f,
        current_price: data[:spot],
        created_at:    Time.current.utc,
        updated_at:    Time.current.utc
      },
      unique_by: %i[ticker snapshot_time]
    )

    { ticker: @ticker, skew_pts: data[:skew_pts], slot: now_slot }
  end

  private

  # Round down to nearest 30-min boundary
  def rounded_slot(time)
    mins = (time.min / 30) * 30
    time.change(min: mins, sec: 0)
  end
end
