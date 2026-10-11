# frozen_string_literal: true

# PMCC v3 §7：純計算層，讀 DB 最新 batch（LEAPS + Short Call），套黃金法則排序，
# 不打 Barchart、不寫 DB。依到期日分桶（Short Call 到期日，最多 8 個），每桶列出 LEAPS ×
# Short Call 交叉組合，通過黃金法則的在前，同組依 max_profit（含收租）由高到低。
class PmccRankingService
  # 與 pmcc_short_call_scraper.py 的 MAX_EXPIRATIONS 對齊——兩邊要一起改。
  # scraper 已經先用 DTE <= 60 篩過，這裡只是防止 DB 裡的舊快照（先前那幾輪
  # 抓的其他到期日）混進來讓桶數超出預期。
  SC_EXPIRATION_COUNT       = 8
  TOP_SHORT_PER_EXPIRATION  = 8
  TOP_COMBOS_PER_EXPIRATION = 5
  # 粗篩區間刻意放寬（2026-09-03）：BTI 這類 5 美元一檔的寬階梯標的，Delta 在價平
  # 附近跳得極陡（10-16 到期：K=55→0.566、K=60→0.180、K=65→0.048），舊的
  # 0.15–0.40 每個到期日最多只夾得到一檔，甚至整桶 0 檔被丟掉。0.05–0.60 讓這些
  # 標的仍有候選可列，是否「建議」交給下面 SHORT_DELTA_OK_* 標記，不在這裡淘汰。
  DELTA_SHORT_MIN           = 0.05
  DELTA_SHORT_MAX           = 0.60
  TOP_LEAPS_PER_GROUP       = 3
  MIN_DTE_GAP               = 180

  # Long 腳門檻：**篩選**條件（leaps-deep-itm-fix.md P4，2026-10-09）。原 §2.3 是
  # 「僅標記、不淘汰」，結果 INTC 組合表的 Long Δ 全是 0.671–0.732，跟建倉規範卡寫的
  # 「Long Delta ≥ 0.80」矛盾。規範卡的數字也從這個常數讀，兩邊不會再脫鉤。
  LEAPS_DELTA_OK_MIN = 0.80
  # §2.3 Short 腳建議標記門檻（僅標記、不淘汰——跟上面的 DELTA_SHORT_* 粗篩是兩條規則）
  SHORT_DELTA_OK_MIN = 0.20
  SHORT_DELTA_OK_MAX = 0.35
  # Short 腳 DTE：**篩選**條件（另案 3，使用者裁示 2026-10-10）。原 §3 是 < 19 天加
  # 警示 badge、> 45 天標「偏遠」但照常列出；改成區間外的到期日不進桶。Δ 仍只標記，
  # 因為寬階梯標的（BTI）在 0.20–0.35 常常整桶 0 檔。建倉規範卡的數字也讀這兩個常數。
  SHORT_DTE_MIN = 19
  SHORT_DTE_MAX = 45

  def initialize(symbol)
    @symbol = symbol.upcase
  end

  def call
    all_leaps = LeapsRankingService.new(@symbol).call
    return { status: :no_leaps, symbol: @symbol } if all_leaps.empty?

    leaps_candidates = select_leaps_candidates(all_leaps)
    return { status: :no_qualified_leaps, symbol: @symbol } if leaps_candidates.empty?

    short_buckets = fetch_short_candidates
    return { status: empty_short_status, symbol: @symbol } if short_buckets.empty?

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
  # P4：先篩 Long Δ ≥ LEAPS_DELTA_OK_MIN，再取 OI 前 TOP_LEAPS_PER_GROUP——順序反過來的話，
  # OI 較高的 Δ 0.6–0.7 腳會把合格腳擠出候選。
  def select_leaps_candidates(all_leaps)
    all = all_leaps.select { |c| c[:delta].present? && c[:delta].to_f >= LEAPS_DELTA_OK_MIN }
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
  # 另案 3：分桶前先只留 DTE SHORT_DTE_MIN..SHORT_DTE_MAX 的列。
  def fetch_short_candidates
    rows = short_rows_in_window
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

  # 最新一批 Short Call 快照（未經 DTE／Delta 篩選）。empty_short_status 也用它分辨沒有桶的原因。
  def latest_short_rows
    @latest_short_rows ||= begin
      latest_at = PmccShortCallSnapshot.for_symbol(@symbol).maximum(:scraped_at)
      latest_at ? PmccShortCallSnapshot.for_symbol(@symbol).where(scraped_at: latest_at).to_a : []
    end
  end

  def short_rows_in_window
    latest_short_rows.select { |r| r.dte.to_i.between?(SHORT_DTE_MIN, SHORT_DTE_MAX) }
  end

  # 沒有任何桶時，分辨是哪一關擋掉的，畫面才說得出實際原因：
  #   完全沒資料 → :no_short；有資料但沒有 19–45 天的到期日 → :no_short_in_window；
  #   區間內有資料、但 Δ 全在 DELTA_SHORT_MIN..MAX 粗篩之外（或 Δ 缺值）→ :no_short_in_delta_range
  #   （審查 pmcc-short-dte-filter r1 質詢 3，使用者裁示另案處理）。
  def empty_short_status
    return :no_short if latest_short_rows.empty?
    return :no_short_in_window if short_rows_in_window.empty?

    :no_short_in_delta_range
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

  # 每桶排序（2026-09-03 定案）：
  #   通過黃金法則 → short_delta_ok → 年化收租率 → max_profit（含 SC）
  #
  # 為什麼 max_profit 不能當主鍵：max_profit = spread - net_debit，KS 拉得越遠
  # spread 越大、max_profit 就越高，排序天然偏袒極價外短腳。粗篩放寬到 0.05–0.60
  # 之後這件事變致命——BTI 實測前 5 名被 Delta 0.06–0.09（權利金 0.38、OI=0，
  # 實務上賣不掉）整排佔滿。max_profit 對 PMCC 本來就只是理論上限，不是決策依據。
  #
  # 為什麼光有 short_delta_ok 不夠：布林標記在 Delta 分佈偏斜的標的上會整排 tie。
  # BTI 那 7 檔候選（0.056/0.064/0.065/0.072/0.087/0.180/0.566）**沒有一檔**落在
  # 0.20–0.35，第二鍵全 false，排序等於沒改。
  #
  # 所以再插一層年化收租率（premium_yield_ann，畫面上本來就有這一欄，使用者看得
  # 懂排序依據）：它是連續值，切得出高下，且正是收租策略真正在意的量。BTI 10-16
  # 桶因此變成 KS=55（權利金 2.03、年化約 122%）排第一，KS=80/85（0.38、OI=0、
  # 年化約 23%）沉底。nil 一律排最後。
  def bucket_and_sort(combos)
    combos.sort_by do |c|
      [
        c[:passes_golden_rule] ? 0 : 1,
        c[:short_delta_ok] ? 0 : 1,
        -(c[:premium_yield_ann] || -Float::INFINITY),
        -(c[:max_profit] || -Float::INFINITY)
      ]
    end
  end
end
