# frozen_string_literal: true

# LEAPS「最划算」推薦（leaps-best-value.md S1）：每個天期區間挑年化時間成本最低的合約。
#
# 輸入是 LeapsRankingService#call 產出的候選 hash。「成交相對清淡」直接讀候選上
# 已算好的 :no_recent_volume_warning——那個門檻是同一批候選的 Vol/OI 相對界線，
# 單筆合約判斷不出來，這裡不另寫一套（S0 質詢 2）。
#
# 三級共同硬條件：bid > 0；exclude_no_recent_trade: true 時排除成交相對清淡的合約。
# 流動性等級：A＝全部條件、B＝Delta＋Spread、C＝只看 Delta。先比等級再比成本，
# 所以次選的年化成本可能低於主推（規格 S3 註記）。
class LeapsBestValueService
  GRADES = %w[A B C].freeze
  REQUIRED_KEYS = %w[delta_min delta_max spread_pct_max oi_min volume_min exclude_no_recent_trade].freeze

  # 規格 S1 公式。外在價值以 ask 計（價差寬自然被懲罰），不讀 DB 以 mid 計的 extrinsic_value。
  # ask／現價缺值或 DTE ≤ 0 → nil（算不出來就不參與，不當成 0）。
  def self.metrics(candidate)
    spot = candidate[:underlying_price]&.to_f
    ask  = candidate[:ask]&.to_f
    dte  = candidate[:dte].to_i
    return nil if spot.nil? || spot <= 0 || ask.nil? || dte <= 0

    strike    = candidate[:strike].to_f
    intrinsic = [ spot - strike, 0.0 ].max
    {
      annual_cost_pct: (ask - intrinsic) / spot * 365 / dte * 100,
      breakeven_pct:   (strike + ask) / spot * 100 - 100,
      spread_pct:      spread_pct(candidate[:bid], ask)
    }
  end

  def self.spread_pct(bid, ask)
    return nil if bid.nil? || ask.nil?

    mid = (bid.to_f + ask.to_f) / 2
    mid.positive? ? (ask.to_f - bid.to_f) / mid * 100 : nil
  end

  def initialize(candidates, config: LeapsBestValueConfig.load)
    missing = REQUIRED_KEYS - config.keys
    raise KeyError, "config/leaps_best_value.yml 缺少：#{missing.join(', ')}" if missing.any?

    @candidates = Array(candidates)
    @config     = config
  end

  def call
    {
      near_term: pick_group(graded_candidates.select { |c| near?(c[:dte]) }),
      far_term:  pick_group(graded_candidates.select { |c| far?(c[:dte]) })
    }
  end

  # 所有候選逐筆算好指標與等級；Delta 區間外或算不出成本的 liquidity_grade 為 nil。
  def graded_candidates
    @graded_candidates ||= @candidates.filter_map do |c|
      m = self.class.metrics(c)
      next if m.nil?

      c.slice(:expiration_date, :dte, :strike, :delta, :bid, :ask, :open_interest, :volume,
              :no_recent_volume_warning)
       .merge(m, liquidity_grade: grade(c, m[:spread_pct]))
    end
  end

  private

  # 天期區間沿用 LeapsRecommendationService 的常數與開閉規則：近 [364, 550]、遠 (550, ∞)。
  def near?(dte)
    dte.to_i.between?(LeapsRecommendationService::NEAR_DTE_MIN, LeapsRecommendationService::NEAR_DTE_MAX)
  end

  def far?(dte)
    dte.to_i > LeapsRecommendationService::FAR_DTE_MIN
  end

  # Delta 區間內完全沒合約 → nil（前端該列不顯示）。
  def pick_group(rows)
    ranked = rows.select { |r| r[:liquidity_grade] }.sort_by { |r| sort_key(r) }
    return nil if ranked.empty?

    { pick: ranked[0], runner_up: ranked[1] }
  end

  # 等級 → 年化成本升冪 → Spread 升冪 → OI 降冪。
  def sort_key(row)
    [ GRADES.index(row[:liquidity_grade]), row[:annual_cost_pct],
      row[:spread_pct] || Float::INFINITY, -row[:open_interest].to_i ]
  end

  # A／B／C 三級共同硬條件不成立 → 不給等級（不能從 B／C 補位進來）。
  def grade(candidate, spread)
    return nil unless hard_requirements_met?(candidate)
    return nil unless delta_in_range?(candidate[:delta])
    return "C" unless spread_ok?(spread)
    return "B" unless liquid?(candidate)

    "A"
  end

  def delta_in_range?(delta)
    delta && delta.to_f.between?(@config.fetch("delta_min"), @config.fetch("delta_max"))
  end

  def spread_ok?(spread)
    spread && spread <= @config.fetch("spread_pct_max")
  end

  # Bid 為 0＝賣不掉；exclude_no_recent_trade: true＝完全不推成交相對清淡的合約。
  def hard_requirements_met?(candidate)
    return false unless candidate[:bid].to_f.positive?
    return false if @config.fetch("exclude_no_recent_trade") && candidate[:no_recent_volume_warning]

    true
  end

  def liquid?(candidate)
    candidate[:open_interest].to_i >= @config.fetch("oi_min") &&
      candidate[:volume].to_i >= @config.fetch("volume_min")
  end
end
