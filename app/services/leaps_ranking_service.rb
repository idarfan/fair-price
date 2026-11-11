# frozen_string_literal: true

class LeapsRankingService
  DEFAULT_DELTA_MIN = 0.60

  MIN_CANDIDATES_FOR_VOL_OI_TIER = 4

  TIER_TOP    = "充足"
  TIER_MID    = "普通"
  TIER_BOTTOM = "偏低"

  def initialize(symbol, delta_min: DEFAULT_DELTA_MIN)
    @symbol    = symbol.upcase
    @delta_min = delta_min
  end

  # 同一列的 volume ÷ OI，不四捨五入。OI 為 nil／0 或 volume 為 nil → nil（資料不足）。
  # 「成交相對清淡」判定只看這個自算值，不讀 Barchart V&G 頁的 vol_oi_ratio
  # （只到小數第 2 位、與 Options 頁不同時間抓、深價內履約價常缺；見 leaps-thin-trading-flag.md）。
  def self.computed_vol_oi(volume, open_interest)
    return nil if volume.nil? || open_interest.nil? || open_interest.to_i.zero?

    volume.to_f / open_interest
  end

  def call
    @all_zero_volume = false
    candidates = fetch_candidates
    return [] if candidates.empty?

    ratios           = candidates.to_h { |row| [ row.id, self.class.computed_vol_oi(row.volume, row.open_interest) ] }
    @all_zero_volume = all_zero?(ratios.values.compact)
    tiers            = liquidity_tiers(candidates)
    # 全 0（多半是開盤前）時相對界線沒有資訊，不逐列標記，改由頁面顯示一行提示。
    vol_oi_floor     = @all_zero_volume ? nil : vol_oi_threshold(candidates.size, ratios.values)

    candidates
      .map { |row| enrich(row, tiers[row.id], ratios[row.id], vol_oi_floor) }
      .sort_by { |e| [ -(e[:open_interest] || 0), -(e[:dte] || 0) ] }
  end

  # 同批有自算值的候選全部為 0 → true。於 #call 之後讀；#call 之前或無候選時為 false。
  def all_zero_volume?
    @all_zero_volume == true
  end

  private

  def all_zero?(ratios)
    ratios.any? && ratios.all?(&:zero?)
  end

  MIN_DTE = 364

  def fetch_candidates
    latest_at = LeapsOptionChainSnapshot.for_symbol(@symbol).calls.maximum(:scraped_at)
    return [] unless latest_at

    LeapsOptionChainSnapshot
      .for_symbol(@symbol)
      .calls
      .where(scraped_at: latest_at)
      .where("dte >= ?", MIN_DTE)
      .where("delta >= ?", @delta_min)
      # 外在價值為負 = 報價本身壞掉（Mid < 內在價值，通常是低成交量下的
      # 過期/失真報價），不是「不建議」而是根本不該被當成候選列出。
      # extrinsic_value 為 null（bid/ask/spot 缺值）維持既有「—」顯示，不在此排除。
      .where("extrinsic_value IS NULL OR extrinsic_value >= 0")
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

  # 33rd percentile boundary of computed Vol/OI (highest value in the bottom third).
  # Returns nil when there are too few candidates to make relative comparison
  # meaningful — callers treat nil as "no warning" rather than flagging everything.
  # 公式與改版前相同，只把輸入從 vol_oi_ratio 換成自算值（leaps-thin-trading-flag S1）。
  def vol_oi_threshold(candidate_count, computed_ratios)
    return nil if candidate_count < MIN_CANDIDATES_FOR_VOL_OI_TIER

    ratios = computed_ratios.compact.sort
    return nil if ratios.empty?

    # Bottom-third count: floor(n/3), minimum 1 row.
    cutoff_count = [ (ratios.size / 3.0).floor, 1 ].max
    ratios[cutoff_count - 1]
  end

  def enrich(row, tier, computed_vol_oi, vol_oi_floor)
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
      computed_vol_oi:          computed_vol_oi,
      underlying_price:         row.underlying_price,
      liquidity_tier:           tier,
      no_recent_volume_warning: low_vol_oi?(computed_vol_oi, vol_oi_floor),
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

  # 自算值 nil（OI 為 0／空）→ 資料不足，不判定（改版前 nil 一律標記，造成誤判）。
  def low_vol_oi?(ratio, floor)
    return false if ratio.nil? || floor.nil?

    ratio <= floor
  end
end
