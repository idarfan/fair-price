# frozen_string_literal: true

class SkewSnapshotService
  HISTORY_PERIOD = 252

  def self.fetch_and_store(ticker)
    new(ticker).call
  end

  def initialize(ticker)
    @ticker = ticker.to_s.upcase.strip
  end

  def call
    data      = IvSidecarService.fetch_skew(@ticker)
    today     = Date.current
    skew_pts  = data[:skew_pts].to_f
    history   = SkewRankDaily.for_ticker(@ticker).ordered
                             .pluck(:skew_pts).map(&:to_f).last(HISTORY_PERIOD)
    skew_rank = compute_rank(skew_pts, history)

    SkewRankDaily.upsert(
      { ticker: @ticker, snapshot_date: today,
        put_iv_025: data[:put_iv_025], call_iv_025: data[:call_iv_025],
        skew_pts: skew_pts, skew_rank: skew_rank,
        created_at: Time.current, updated_at: Time.current },
      unique_by: [ :ticker, :snapshot_date ]
    )

    { ticker: @ticker, skew_pts: skew_pts, skew_rank: skew_rank }
  end

  private

  def compute_rank(current, history)
    return nil if history.size < 5

    count_below = history.count { |v| v < current }
    (count_below.to_f / history.size * 100).round(2)
  end
end
