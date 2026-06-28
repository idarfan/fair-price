# frozen_string_literal: true

class LeapsRankingService
  DEFAULT_DELTA_MIN = 0.75
  DEFAULT_DELTA_MAX = 0.90

  TIER_TOP    = "充足"
  TIER_MID    = "普通"
  TIER_BOTTOM = "偏低"

  def initialize(symbol, delta_min: DEFAULT_DELTA_MIN, delta_max: DEFAULT_DELTA_MAX)
    @symbol    = symbol.upcase
    @delta_min = delta_min
    @delta_max = delta_max
  end

  def call
    candidates = fetch_candidates
    return [] if candidates.empty?

    tiers         = liquidity_tiers(candidates)
    vol_oi_floor  = vol_oi_threshold(candidates)

    candidates
      .map { |row| enrich(row, tiers[row.id], vol_oi_floor) }
      .sort_by { |e| [-(e[:open_interest] || 0), -(e[:dte] || 0)] }
  end

  private

  def fetch_candidates
    latest_at = LeapsOptionChainSnapshot.for_symbol(@symbol).calls.maximum(:scraped_at)
    return [] unless latest_at

    LeapsOptionChainSnapshot
      .for_symbol(@symbol)
      .calls
      .where(scraped_at: latest_at)
      .where(delta: @delta_min..@delta_max)
      .to_a
  end

  # Rank-based: sort by OI desc, split into thirds by rank index.
  # Different tickers have wildly different OI magnitudes; absolute
  # thresholds would be either too tight or too loose across symbols.
  def liquidity_tiers(candidates)
    sorted        = candidates.sort_by { |r| -(r.open_interest || 0) }
    n             = sorted.size
    top_boundary  = n / 3
    bot_boundary  = (2 * n) / 3

    sorted.each_with_index.with_object({}) do |(row, idx), hash|
      hash[row.id] = if idx < top_boundary then TIER_TOP
                     elsif idx < bot_boundary then TIER_MID
                     else TIER_BOTTOM
                     end
    end
  end

  # Bottom third of vol_oi_ratio in this result set is the "近期無成交" floor.
  # Avoids hardcoding a number for a ratio whose scale differs by ticker.
  def vol_oi_threshold(candidates)
    ratios = candidates.filter_map { |r| r.vol_oi_ratio&.to_f }.sort
    return nil if ratios.empty?

    cutoff_idx = [ (ratios.size / 3.0).ceil - 1, 0 ].max
    ratios[cutoff_idx]
  end

  def enrich(row, tier, vol_oi_floor)
    mid         = row.mid_price
    underlying  = row.underlying_price.to_f
    strike      = row.strike.to_f
    intrinsic   = [ underlying - strike, 0.0 ].max
    time_value  = mid ? mid.to_f - intrinsic : nil

    {
      snapshot:               row,
      expiration_date:        row.expiration_date,
      dte:                    row.dte,
      strike:                 row.strike,
      delta:                  row.delta,
      open_interest:          row.open_interest,
      volume:                 row.volume,
      bid:                    row.bid,
      ask:                    row.ask,
      mid:                    mid,
      iv:                     row.iv,
      vega:                   row.vega,
      itm_probability:        row.itm_probability,
      vol_oi_ratio:           row.vol_oi_ratio,
      underlying_price:       row.underlying_price,
      liquidity_tier:         tier,
      no_recent_volume_warning: low_vol_oi?(row.vol_oi_ratio, vol_oi_floor),
      time_value_pct:         calc_time_value_pct(time_value, underlying),
      bid_ask_spread_pct:     calc_spread_pct(row.bid, row.ask, mid)
    }
  end

  def calc_time_value_pct(time_value, underlying)
    return nil if time_value.nil? || underlying.zero?

    time_value / underlying
  end

  def calc_spread_pct(bid, ask, mid)
    return nil if bid.nil? || ask.nil? || mid.nil? || mid.to_f.zero?

    (ask.to_f - bid.to_f) / mid.to_f
  end

  def low_vol_oi?(ratio, floor)
    return true  if ratio.nil?
    return false if floor.nil?

    ratio.to_f <= floor
  end
end
