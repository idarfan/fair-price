# frozen_string_literal: true

# PMCC v3 §7：純計算層，讀 DB 最新 batch（LEAPS + Short Call），套黃金法則排序，
# 不打 Barchart、不寫 DB。三個到期日分桶（Short Call 到期日），每桶列出 LEAPS ×
# Short Call 交叉組合，通過黃金法則的在前，同組依 max_profit（含收租）由高到低。
class PmccRankingService
  SC_EXPIRATION_COUNT       = 3
  TOP_SHORT_PER_EXPIRATION  = 8
  TOP_COMBOS_PER_EXPIRATION = 5
  DELTA_SHORT_MIN           = 0.15
  DELTA_SHORT_MAX           = 0.40
  TOP_LEAPS_PER_GROUP       = 3
  MIN_DTE_GAP               = 180

  # §2.3 建議標記門檻（僅標記、不淘汰——跟上面的粗篩門檻是兩條互不取代的規則）
  LEAPS_DELTA_OK_MIN = 0.80
  SHORT_DELTA_OK_MIN = 0.20
  SHORT_DELTA_OK_MAX = 0.35

  def initialize(symbol)
    @symbol = symbol.upcase
  end

  def call
    leaps_candidates = fetch_leaps_candidates
    return { status: :no_leaps, symbol: @symbol } if leaps_candidates.empty?

    short_buckets = fetch_short_candidates
    return { status: :no_short, symbol: @symbol } if short_buckets.empty?

    bucket_keys = short_buckets.keys # 升序 ISO 日期字串，來自 fetch_short_candidates 已排序

    result         = {}
    total_combos   = 0
    passing_combos = 0

    bucket_keys.each do |exp_key|
      sc_rows = short_buckets[exp_key]
      combos  = cross_and_filter(leaps_candidates, sc_rows)
      total_combos   += combos.size
      passing_combos += combos.count { |c| c[:passes_golden_rule] }

      sorted_combos = bucket_and_sort(combos).first(TOP_COMBOS_PER_EXPIRATION)

      result[exp_key] = {
        expiration:      exp_key,
        expiration_date: Date.parse(exp_key),
        short_dte:       sc_rows.first[:dte],
        combos:          sorted_combos,
        has_passing:     sorted_combos.any? { |c| c[:passes_golden_rule] }
      }
    end

    result[:near_term] = result[bucket_keys[0]]
    result[:mid_term]  = result[bucket_keys[1]] if bucket_keys[1]
    result[:far_term]  = result[bucket_keys[2]] if bucket_keys[2]

    result[:summary] = {
      total_combos:   total_combos,
      passing_combos: passing_combos,
      leaps_count:    leaps_candidates.size,
      short_count:    short_buckets.values.sum(&:size),
      symbol:         @symbol,
      expirations:    bucket_keys
    }
    result[:status] = :ok
    result
  end

  private

  # §7 step1：LEAPS 候選沿用 LeapsRankingService（同一套流動性分級/Delta 篩選，
  # 不重寫）。近天期/遠天期邊界沿用 LeapsRecommendationService 既有常數
  # （NEAR_DTE_MIN/MAX=364/550、FAR_DTE_MIN=550），不另造第二份定義。
  def fetch_leaps_candidates
    all = LeapsRankingService.new(@symbol).call
    return [] if all.empty?

    near = all.select do |c|
      c[:dte].to_i >= LeapsRecommendationService::NEAR_DTE_MIN &&
        c[:dte].to_i <= LeapsRecommendationService::NEAR_DTE_MAX
    end.first(TOP_LEAPS_PER_GROUP)

    far = all.select { |c| c[:dte].to_i > LeapsRecommendationService::FAR_DTE_MIN }
             .first(TOP_LEAPS_PER_GROUP)

    near + far
  end

  # §7 step2：Short Call 候選——最新 batch，按到期日分桶（升序，取前 3），每桶
  # Delta 0.15–0.40 粗篩後 OI 降序取前 8。這裡只做粗篩（是否列入運算），不做
  # 0.20–0.35 的「建議標記」篩選——那是列出後才標 ✅/⚠️ 的事，見 §2.3。
  def fetch_short_candidates
    latest_at = PmccShortCallSnapshot.for_symbol(@symbol).maximum(:scraped_at)
    return {} unless latest_at

    rows = PmccShortCallSnapshot.for_symbol(@symbol).where(scraped_at: latest_at).to_a
    return {} if rows.empty?

    grouped = rows.group_by { |r| r.expiration_date.to_s }

    grouped.keys.sort.first(SC_EXPIRATION_COUNT).each_with_object({}) do |exp_key, acc|
      filtered = grouped[exp_key].select do |r|
        r.delta.present? && r.delta.to_f >= DELTA_SHORT_MIN && r.delta.to_f <= DELTA_SHORT_MAX
      end
      sorted = filtered.sort_by { |r| -(r.open_interest || 0) }.first(TOP_SHORT_PER_EXPIRATION)
      acc[exp_key] = sorted.map { |r| build_short_leg(r) } unless sorted.empty?
    end
  end

  def build_short_leg(row)
    {
      strike:            row.strike,
      mid:               row.mid_price,
      bid:               row.bid,
      ask:               row.ask,
      theoretical_price: row.theoretical_price,
      moneyness:         row.moneyness,
      delta:             row.delta,
      gamma:             row.gamma,
      theta:             row.theta,
      vega:              row.vega,
      iv:                row.iv,
      itm_probability:   row.itm_probability,
      vol:               row.volume,
      oi:                row.open_interest,
      vol_oi_ratio:      row.vol_oi_ratio,
      oi_change:         row.oi_change,
      expiration_date:   row.expiration_date,
      dte:               row.dte
    }
  end

  def build_long_leg(candidate)
    {
      strike:          candidate[:strike],
      mid:             candidate[:mid],
      bid:             candidate[:bid],
      ask:             candidate[:ask],
      delta:           candidate[:delta],
      dte:             candidate[:dte],
      oi:              candidate[:open_interest],
      expiration_date: candidate[:expiration_date],
      intrinsic:       candidate[:intrinsic_value],
      extrinsic:       candidate[:extrinsic_value]
    }
  end

  # §7 step3 + §2.2：前置檢查依序 (a) KS>KL (b) DTE 差距 (c) mid 缺值。
  # (a)(b) 未過仍保留（記 fail_reason，讓表格照常顯示該列並標紅）；
  # (c) 直接不列入（不進 combos，不是顯示 0）。
  def cross_and_filter(leaps_candidates, sc_rows)
    combos = []
    leaps_candidates.each do |long_c|
      sc_rows.each do |short_c|
        pl = long_c[:mid]
        ps = short_c[:mid]
        next if pl.nil? || ps.nil? # (c)

        combos << build_combo(long_c, short_c, pl.to_f, ps.to_f)
      end
    end
    combos
  end

  def build_combo(long_c, short_c, pl, ps)
    kl     = long_c[:strike].to_f
    ks     = short_c[:strike].to_f
    spread = ks - kl

    passes, fail_reason = evaluate_golden_rule(kl, ks, pl, spread, long_c[:dte], short_c[:dte])

    net_debit        = pl - ps
    max_profit_no_sc = spread - pl
    max_profit       = spread - net_debit
    short_dte_i      = short_c[:dte].to_i

    premium_yield = net_debit.zero? ? nil : (ps / net_debit) * 100.0
    premium_yield_ann = if premium_yield.nil? || short_dte_i <= 0
                          nil
    else
                          premium_yield / short_dte_i * 365.0
    end

    {
      long_leg:           build_long_leg(long_c),
      short_leg:          short_c,
      spread:             spread,
      net_debit:          net_debit,
      max_profit_no_sc:   max_profit_no_sc,
      max_profit:         max_profit,
      premium_yield:      premium_yield,
      premium_yield_ann:  premium_yield_ann,
      passes_golden_rule: passes,
      fail_reason:        fail_reason,
      leaps_delta_ok:     long_c[:delta].present? && long_c[:delta].to_f >= LEAPS_DELTA_OK_MIN,
      short_delta_ok:     short_c[:delta].present? &&
                           short_c[:delta].to_f >= SHORT_DELTA_OK_MIN &&
                           short_c[:delta].to_f <= SHORT_DELTA_OK_MAX
    }
  end

  # §2.2 前置檢查，依序：(a) KS>KL (b) long.dte >= short.dte+180 (c) 由呼叫端
  # 在 cross_and_filter 處理（mid 缺值不進這個方法）。通過兩項前置後才看
  # passes = PL < spread（嚴格小於），未過附上帶數值的 fail_reason。
  def evaluate_golden_rule(kl, ks, pl, spread, long_dte, short_dte)
    if ks <= kl
      return [ false, format("Short Call履約價KS($%s)必須大於LEAPS履約價KL($%s)", fmt_dollar(ks), fmt_dollar(kl)) ]
    end

    long_dte_i  = long_dte.to_i
    short_dte_i = short_dte.to_i
    if long_dte.nil? || short_dte.nil? || long_dte_i < short_dte_i + MIN_DTE_GAP
      return [ false, format(
        "LEAPS到期日(%d天)距Short Call到期日(%d天)不足180天，SC到期時LEAPS時間價值恐已大幅流失，最大獲利公式不成立",
        long_dte_i, short_dte_i
      ) ]
    end

    if pl < spread
      [ true, nil ]
    else
      [ false, format("PL(%.2f) >= Spread(%.2f)", pl, spread) ]
    end
  end

  # $250.00 -> "250"；$8.50 -> "8.5"（配合規格範例的整數美元不帶小數點寫法，
  # 同時保留非整數履約價的實際小數）。
  def fmt_dollar(val)
    format("%.2f", val).sub(/\.?0+$/, "")
  end

  # 每桶排序：通過黃金法則的在前，同組依 max_profit（含 SC）高到低。
  def bucket_and_sort(combos)
    combos.sort_by { |c| [ c[:passes_golden_rule] ? 0 : 1, -(c[:max_profit] || -Float::INFINITY) ] }
  end
end
