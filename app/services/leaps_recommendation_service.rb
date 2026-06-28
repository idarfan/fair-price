# frozen_string_literal: true

class LeapsRecommendationService
  NEAR_DTE_MIN = 364
  NEAR_DTE_MAX = 550
  FAR_DTE_MIN  = 550

  TIER_ORDER = { "充足" => 3, "普通" => 2, "偏低" => 1 }.freeze

  HIGH_SPREAD_THRESHOLD = 0.05

  def initialize(candidates)
    @candidates = Array(candidates)
  end

  def call
    {
      near_term: recommend_group(
        @candidates.select { |c| c[:dte].to_i >= NEAR_DTE_MIN && c[:dte].to_i <= NEAR_DTE_MAX },
        "近天期"
      ),
      far_term: recommend_group(
        @candidates.select { |c| c[:dte].to_i > FAR_DTE_MIN },
        "遠天期"
      )
    }
  end

  private

  def recommend_group(group, label)
    return { no_candidates: true, label: label, pick: nil, runner_up: nil, reason: nil } if group.empty?

    all_warned  = group.all? { |c| c[:no_recent_volume_warning] }
    eligible    = all_warned ? group : group.reject { |c| c[:no_recent_volume_warning] }
    sorted      = sort_by_liquidity(eligible)
    pick        = sorted[0]
    runner_up   = sorted[1]

    {
      no_candidates: false,
      label:         label,
      all_warned:    all_warned,
      pick:          pick,
      runner_up:     runner_up,
      reason:        build_reason(pick, runner_up, all_warned)
    }
  end

  def sort_by_liquidity(candidates)
    candidates.sort_by { |c| [ -TIER_ORDER.fetch(c[:liquidity_tier].to_s, 0), -(c[:open_interest] || 0) ] }
  end

  def build_reason(pick, runner_up, all_warned)
    parts = []

    parts << sprintf(
      "建議到期日：%s（DTE %d），履約價 $%s，Delta %s，Mid $%s。",
      pick[:expiration_date], pick[:dte].to_i,
      fmt_price(pick[:strike]), fmt_decimal(pick[:delta], 3), fmt_price(pick[:mid])
    )

    if runner_up
      parts << sprintf(
        "此履約價 OI 為 %s，為此天期區間最高；次選履約價 $%s（%s）OI 為 %s，流動性相對較差。",
        fmt_int(pick[:open_interest]),
        fmt_price(runner_up[:strike]), runner_up[:expiration_date],
        fmt_int(runner_up[:open_interest])
      )
    else
      parts << sprintf("此天期區間僅此一個候選，OI 為 %s。", fmt_int(pick[:open_interest]))
    end

    if pick[:time_value_pct]
      parts << sprintf(
        "Time Value 溢價約 %s（相較直接持股多負擔的時間價值成本）。",
        fmt_pct(pick[:time_value_pct])
      )
    end

    if pick[:bid_ask_spread_pct]
      if pick[:bid_ask_spread_pct].to_f > HIGH_SPREAD_THRESHOLD
        parts << sprintf(
          "⚠️ Bid-Ask Spread 偏高（%s），進出場成本較大，建議使用限價單。",
          fmt_pct(pick[:bid_ask_spread_pct])
        )
      else
        parts << sprintf("Bid-Ask Spread %s，進出場成本合理。", fmt_pct(pick[:bid_ask_spread_pct]))
      end
    end

    if pick[:vega] && pick[:iv]
      parts << sprintf(
        "IV %s，Vega %s；若未來 IV 回落，每個百分點 IV 變化對此合約的影響約為 Vega 值，需留意 IV Crush 風險。",
        fmt_pct(pick[:iv]), fmt_decimal(pick[:vega], 4)
      )
    end

    if all_warned
      parts << "⚠️ 注意：此天期區間所有候選均有「近期無成交」警示，目前市場成交清淡，進出場可能有困難。"
    elsif pick[:no_recent_volume_warning]
      parts << "⚠️ 注意：此推薦候選本身有「近期無成交」警示，需留意進出場流動性。"
    end

    parts << "以上為流動性與 Greeks 篩選後的推薦結果，僅供策略篩選參考，非投資建議，請自行評估。"

    parts.join("\n")
  end

  def fmt_int(val)
    return "—" if val.nil?

    n = val.to_i
    n.abs >= 1_000 ? sprintf("%d", n).reverse.scan(/\d{1,3}/).join(",").reverse : n.to_s
  end

  def fmt_price(val)
    return "—" if val.nil?

    sprintf("%.2f", val.to_f)
  end

  def fmt_decimal(val, digits)
    return "—" if val.nil?

    sprintf("%.#{digits}f", val.to_f)
  end

  def fmt_pct(val)
    return "—" if val.nil?

    sprintf("%.1f%%", val.to_f * 100)
  end
end
