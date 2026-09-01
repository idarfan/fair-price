# frozen_string_literal: true

# pmcc-tracker Phase 3：對「已持有的 PMCC 部位」給滾倉候選。
#
# 與 PmccRankingService 平行放置、刻意不合併：那支回答「現在要建倉的話，
# 哪組 LEAPS × Short Call 最好」，這支回答「我手上這一腳該滾去哪裡」——
# 輸入（既有部位 vs 全市場交叉）、基準（實付成本 vs 現在市價）都不同。
#
# 純計算層：不打 Barchart、不寫 DB、不自動執行滾倉。
class PmccRollSuggestionService
  # 滾倉專用的 Delta 區間，比建倉窄（PmccRankingService 是 0.15–0.40 粗篩、
  # 建倉規範標記區間 0.20–0.35）。滾倉時長腳成本已經沉下去，目標是穩定收租
  # 而非最大化權利金，所以取偏保守的一段。三組數字各有用途，不強行統一。
  DELTA_MIN = 0.15
  DELTA_MAX = 0.30

  # lesson9 建倉規範的天期區間。**區間外不過濾、只標記**——同本專案
  # 「列出全部候選、只標分級、不自動下結論」的原則。
  DTE_MIN = 19
  DTE_MAX = 45

  TOP_N = 5

  def self.call(position, candidates:, current_quote: nil, long_quote: :lookup)
    new(position, candidates: candidates, current_quote: current_quote, long_quote: long_quote).call
  end

  def initialize(position, candidates:, current_quote: nil, long_quote: :lookup)
    @position      = position
    @candidates    = Array(candidates)
    @current_quote = current_quote
    @long_quote    = long_quote
  end

  def call
    return { status: :no_open_leg, suggestions: [] } if open_leg.blank?
    return { status: :no_buyback_quote, suggestions: [] } if buyback_cost.nil?

    rows = eligible_candidates.map { |c| build_suggestion(c) }
    rows = rows.sort_by { |r| [ r[:passes_golden_rule] ? 0 : 1, -r[:max_profit].to_f ] }

    {
      status:       rows.any? ? :ok : :no_candidates,
      buyback_cost: buyback_cost,
      current_leg:  { strike: to_f(open_leg.short_strike), expiration: open_leg.short_expiration },
      long_leg:     long_leg_summary,
      suggestions:  rows.first(TOP_N)
    }
  end

  # 長腳的「實付成本」與「目前市價」並列：計算一律用實付成本（黃金法則、
  # NetDebit、MaxProfit 都是），市價只給畫面顯示，讓使用者看得到帳面浮動。
  # 兩個數字必須標清楚哪個是哪個，混用會讓損益帳本失去意義。
  def long_leg_summary
    quote = resolved_long_quote
    market = to_f(fetch(quote, :mid))

    {
      strike:      to_f(@position.long_strike),
      expiration:  @position.long_expiration,
      entry_cost:  to_f(@position.long_entry_cost),   # ← 計算基準
      market_mid:  market,                            # ← 僅供顯示
      market_delta: to_f(fetch(quote, :delta)),
      quoted_at:   fetch(quote, :scraped_at),
      unrealized_per_share: market.present? ? (market - to_f(@position.long_entry_cost)).round(4) : nil
    }
  end

  # 預設查 pmcc_leg_quotes（Phase 0 的落點）；測試或呼叫端可直接注入。
  def resolved_long_quote
    return @long_quote unless @long_quote == :lookup

    @resolved_long_quote ||= PmccLegQuote.for_leg(
      @position.ticker, @position.long_expiration, @position.long_strike
    )
  end

  private

  def open_leg
    @open_leg ||= @position.open_short_leg
  end

  # 買回目前這一腳要花多少（每股）。沒有報價就不能算滾動淨現金流——
  # 硬給 0 會讓每個候選的現金流都灌水，寧可明確回報缺報價。
  def buyback_cost
    return @buyback_cost if defined?(@buyback_cost)

    @buyback_cost = to_f(fetch(@current_quote, :mid) || fetch(@current_quote, :mid_price))
  end

  # 只往上滾（roll up），不含 roll down：往下滾等於把履約價讓給對手，
  # 現有部位的黃金法則會更難成立。
  def eligible_candidates
    @candidates.select do |c|
      strike = to_f(fetch(c, :strike))
      delta  = to_f(fetch(c, :delta))
      mid    = to_f(fetch(c, :mid) || fetch(c, :mid_price))

      strike.present? && mid.present? && delta.present? &&
        strike > to_f(open_leg.short_strike) &&
        delta >= DELTA_MIN && delta <= DELTA_MAX
    end
  end

  def build_suggestion(candidate)
    strike  = to_f(fetch(candidate, :strike))
    mid     = to_f(fetch(candidate, :mid) || fetch(candidate, :mid_price))
    dte     = fetch(candidate, :dte)&.to_i
    spread  = strike - to_f(@position.long_strike)

    # 滾動淨現金流 = 賣新腳收到的 − 買回舊腳付出的（每股）
    roll_cash = mid - buyback_cost

    # NetDebit 以**實付成本**為基準（2026-09-01 決定），跟損益帳本同一把尺：
    # 回答「這筆交易到最後我真的賺不賺錢」，而不是「今天重建划不划算」。
    net_debit  = to_f(@position.long_entry_cost) - (collected_so_far + roll_cash)
    max_profit = spread - net_debit

    passes, fail_reason = evaluate_golden_rule(spread, net_debit, dte)

    {
      strike:             strike,
      expiration:         fetch(candidate, :expiration_date),
      dte:                dte,
      delta:              to_f(fetch(candidate, :delta)),
      mid:                mid,
      spread:             spread.round(4),
      roll_cash_flow:     roll_cash.round(4),
      net_debit:          net_debit.round(4),
      max_profit:         max_profit.round(4),
      passes_golden_rule: passes,
      fail_reason:        fail_reason,
      in_suggested_dte:   dte.present? && dte >= DTE_MIN && dte <= DTE_MAX
    }
  end

  # 這一腳之前已經收到的淨額（每股）：歷史短腳的收租減去買回成本。
  # 目前這一腳的收租也算在內，因為滾倉時它會被買回（買回成本已在 roll_cash）。
  def collected_so_far
    @collected_so_far ||= @position.short_legs.sum do |leg|
      to_f(leg.premium_collected) - to_f(leg.close_cost || 0)
    end
  end

  # 方向與 PmccRankingService#evaluate_golden_rule 一致：**NetDebit < Spread 才通過**。
  # pmcc-tracker.md 原本寫成 `PL >= Spread 通過`，與它自己引用的
  # `P_L < K_S − K_L` 以及既有實作都相反，已於 2026-09-01 修正。
  def evaluate_golden_rule(spread, net_debit, dte)
    if spread <= 0
      return [ false, format("新履約價必須大於長腳履約價（Spread %.2f）", spread) ]
    end

    long_dte = (@position.long_expiration - Date.current).to_i
    if dte.present? && long_dte < dte + PmccRankingService::MIN_DTE_GAP
      return [ false, format(
        "長腳(%d天)距新短腳(%d天)不足%d天，SC到期時長腳時間價值恐已大幅流失，最大獲利公式不成立",
        long_dte, dte, PmccRankingService::MIN_DTE_GAP
      ) ]
    end

    return [ true, nil ] if net_debit < spread

    [ false, format("NetDebit(%.2f) >= Spread(%.2f)", net_debit, spread) ]
  end

  def fetch(source, key)
    return nil if source.blank?

    if source.respond_to?(key) then source.public_send(key)
    elsif source.respond_to?(:[]) then source[key] || source[key.to_s]
    end
  end

  def to_f(val)
    val.nil? ? nil : val.to_f
  end
end
