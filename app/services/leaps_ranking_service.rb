# frozen_string_literal: true

class LeapsRankingService
  DEFAULT_DELTA_MIN = 0.60
  DEFAULT_DELTA_MAX = 0.90

  MIN_CANDIDATES_FOR_VOL_OI_TIER = 4

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

    tiers        = liquidity_tiers(candidates)
    vol_oi_floor = vol_oi_threshold(candidates)

    candidates
      .map { |row| enrich(row, tiers[row.id], vol_oi_floor) }
      .sort_by { |e| [-(e[:open_interest] || 0), -(e[:dte] || 0)] }
  end

  private

  MIN_DTE = 364

  def fetch_candidates
    latest_at = LeapsOptionChainSnapshot.for_symbol(@symbol).calls.maximum(:scraped_at)
    return [] unless latest_at

    LeapsOptionChainSnapshot
      .for_symbol(@symbol)
      .calls
      .where(scraped_at: latest_at)
      .where("dte >= ?", MIN_DTE)
      .where(delta: @delta_min..@delta_max)
      .to_a
  end

  # Value-based percentile: compute 33rd and 67th OI percentile values, then
  # assign tier by comparing each row's OI against those thresholds.
  # Same OI always gets the same tier, regardless of sort order.
  def liquidity_tiers(candidates)
    ois = candidates.map { |r| r.open_interest || 0 }.sort
    n   = ois.size
    p33 = ois[(n / 3.0).floor]
    p67 = ois[(2 * n / 3.0).floor]

    candidates.each_with_object({}) do |row, hash|
      oi = row.open_interest || 0
      hash[row.id] = if oi >= p67 then TIER_TOP
                     elsif oi >= p33 then TIER_MID
                     else TIER_BOTTOM
                     end
    end
  end

  # 33rd percentile boundary of vol_oi_ratio (highest value in the bottom third).
  # Returns nil when there are too few candidates to make relative comparison
  # meaningful — callers treat nil as "no warning" rather than flagging everything.
  def vol_oi_threshold(candidates)
    return nil if candidates.size < MIN_CANDIDATES_FOR_VOL_OI_TIER

    ratios = candidates.filter_map { |r| r.vol_oi_ratio&.to_f }.sort
    return nil if ratios.empty?

    # Bottom-third count: floor(n/3), minimum 1 row.
    cutoff_count = [ (ratios.size / 3.0).floor, 1 ].max
    ratios[cutoff_count - 1]
  end

  def enrich(row, tier, vol_oi_floor)
    mid        = row.mid_price
    underlying = row.underlying_price.to_f
    # Phase H：內在/外在價值直接讀 persist 層算好的 DB 欄位，排行層不重算
    # （公式唯一定義在 LeapsOptionChainSnapshot.derived_values）。
    time_value = row.extrinsic_value&.to_f

    {
      snapshot:                 row,
      expiration_date:          row.expiration_date,
      dte:                      row.dte,
      strike:                   row.strike,
      delta:                    row.delta,
      open_interest:            row.open_interest,
      volume:                   row.volume,
      bid:                      row.bid,
      ask:                      row.ask,
      mid:                      mid,
      iv:                       row.iv,
      vega:                     row.vega,
      itm_probability:          row.itm_probability,
      vol_oi_ratio:             row.vol_oi_ratio,
      underlying_price:         row.underlying_price,
      liquidity_tier:           tier,
      no_recent_volume_warning: low_vol_oi?(row.vol_oi_ratio, vol_oi_floor),
      intrinsic_value:          row.intrinsic_value,
      extrinsic_value:          row.extrinsic_value,
      extrinsic_pct:            calc_extrinsic_pct(row.extrinsic_value, mid),
      time_value_pct:           calc_time_value_pct(time_value, underlying),
      bid_ask_spread_pct:       calc_spread_pct(row.bid, row.ask, mid)
    }
  end

  # 外在佔比 = extrinsic_value / mid（display 層計算，不落地）。
  # 分母是權利金 Mid（「這口權利金裡有多少比例是保險費」），跟 time_value_pct
  # 的分母 underlying_price（「相對持股多付幾 % 溢價」）是兩個不同指標。
  # mid <= 0 或任一缺值 → nil（畫面顯示「—」，不是 0% 或 NaN）。
  def calc_extrinsic_pct(extrinsic, mid)
    return nil if extrinsic.nil? || mid.nil? || mid.to_f <= 0

    extrinsic.to_f / mid.to_f
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
    return true  if ratio.nil? && floor  # nil ratio is suspicious only when we have a floor
    return false if floor.nil?

    ratio.to_f <= floor
  end
end
