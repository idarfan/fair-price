# frozen_string_literal: true

# 推薦分析的「💰 最划算」卡與兩卡共用的欄位列表（leaps-best-value.md S3）。
#
# 左卡吃 LeapsBestValueService 的結果（@best_value），右卡是既有 OI 推薦；兩卡的欄位列表
# 用同一支 render_metric_list，指標一律由 LeapsBestValueService.metrics 算（公式只有一份）。
# 門檻與註記數值只讀 LeapsBestValueConfig，天期邊界只讀 LeapsRecommendationService 常數。
module LeapsRecommendations::BestValueCards
  include LeapsRecommendations::SharedConstants
  IV_WARN_TEXT = "優先深度價內以降低 Vega 與外在價值"

  def best_value_group(term) = @best_value&.dig(term)

  def best_value_config = (@best_value_config ||= LeapsBestValueConfig.load)

  # 左卡。區間內沒有任何合格合約（group 為 nil）就整張不畫，不顯示任何「無合格」字樣。
  def render_best_value_card(group, oi_pick)
    return if group.nil?

    pick = group[:pick]
    div(class: "rounded-lg border border-emerald-200 bg-emerald-50/40 p-3", data_leaps_best_value_card: "") do
      div(class: "flex flex-wrap items-center gap-2 mb-2") do
        h4(class: "text-xs font-semibold text-emerald-700") { plain "💰 最划算（最低年化時間成本）" }
        if same_contract?(pick, oi_pick)
          span(class: "text-[10px] px-1.5 py-0.5 rounded bg-emerald-100 text-emerald-700 border border-emerald-200") do
            plain "與流動性最佳相同"
          end
        end
      end
      # leaps-best-value-card-style S1：與流動性最佳卡同一結構（共用 PickCardParts）。
      # 膠囊固定綠色（使用者裁示 2a）；主推的「⚠ 成交相對清淡」接在膠囊後（原本接在合約標題後）。
      runner_up = group[:runner_up]
      render_capsule_row(pick, runner_up: runner_up, style: LIQUIDITY_STYLE["充足"]) do
        render_thin_trading_flag(pick)
      end
      render_pick_reason(best_value_reason_text(pick))
      render_pick_details(pick, runner_up)
    end
  end

  # 說明文字（規格 S1 第 3 點範本）。
  def best_value_reason_text(pick)
    [
      "建議到期日：#{pick[:expiration_date]}（DTE #{pick[:dte].to_i}），履約價 #{sprintf('$%.2f', pick[:strike].to_f)}，" \
      "Delta #{fmt_decimal(pick[:delta], 3)}，Mid $#{fmt_price(mid_of(pick))}。",
      "年化時間成本 #{fmt_cost_pct(pick[:annual_cost_pct])}，股價需漲 #{fmt_cost_pct(pick[:breakeven_pct])} 才損益兩平。",
      "Bid-Ask Spread #{fmt_cost_pct(pick[:spread_pct])}。",
      "以上依「預設選擇標準」篩選，僅供策略篩選參考，非投資建議，請自行評估。"
    ].join("\n")
  end

  def same_contract?(a, b)
    a && b && a[:expiration_date].to_s == b[:expiration_date].to_s && a[:strike].to_f == b[:strike].to_f
  end

  # IV 偏高警示：LEAPS IV Rank 優先，累積未滿時退回 IV 環境區塊的 Barchart IV Rank；兩者皆無不顯示。
  def render_iv_high_warning
    source, rank = iv_warning_rank
    return if rank.nil? || rank < best_value_config.fetch("iv_rank_warn")

    p(class: "text-xs text-amber-700 mt-1", data_leaps_iv_high_warning: "") do
      plain "IV 偏高（#{source} IV Rank #{rank}），#{IV_WARN_TEXT}"
    end
  end

  def iv_warning_rank
    env = @iv_environment.is_a?(Hash) ? @iv_environment : {}
    return [ "LEAPS", env[:rank].round ] unless env[:rank].nil?

    barchart = env[:barchart].is_a?(Hash) ? env[:barchart][:iv_rank] : nil
    barchart.nil? ? [ nil, nil ] : [ "Barchart", barchart.round ]
  end

  # 推薦內容最底下（名詞解釋圖卡之前）的「預設選擇標準」。數字全部讀設定檔與既有常數。
  def render_selection_criteria
    div(class: "px-4 py-3 border-t border-gray-100 bg-gray-50 text-xs text-gray-600", data_leaps_selection_criteria: "") do
      p(class: "font-semibold text-gray-700 mb-1") { plain "預設選擇標準" }
      ol(class: "list-decimal pl-5 space-y-0.5") do
        selection_criteria_items.each { |text| li { plain text } }
      end
      selection_criteria_notes.each { |text| p(class: "mt-1") { plain text } }
    end
  end

  def selection_criteria_items
    cfg = best_value_config
    [
      "排序：年化時間成本最低者優先 ＝（Ask − 內在價值）÷ 現價 × 365 ÷ DTE。同值依 Spread 小、OI 大排序。",
      "Delta #{sprintf('%.2f', cfg.fetch('delta_min'))}–#{sprintf('%.2f', cfg.fetch('delta_max'))}（深度價內，接近持股）",
      "Spread（買賣差價比）≤ #{sprintf('%g', cfg.fetch('spread_pct_max'))}%",
      "OI ≥ #{fmt_int(cfg.fetch('oi_min'))}",
      "當日成交量 ≥ #{fmt_int(cfg.fetch('volume_min'))}",
      cfg.fetch("exclude_no_recent_trade") ? "成交相對清淡合約不列入" : "成交相對清淡合約照常列入",
      "天期：近天期 DTE #{LeapsRecommendationService::NEAR_DTE_MIN}–#{LeapsRecommendationService::NEAR_DTE_MAX}" \
      "／遠天期 DTE 超過 #{LeapsRecommendationService::FAR_DTE_MIN}，各自挑選"
    ]
  end

  def selection_criteria_notes
    [
      "若符合 2–5 的合約不足兩檔，依序放寬：先忽略 OI 與成交量，再忽略 Spread，只保留 Delta 區間。",
      "排序先比流動性等級，同等級再比年化成本，因此次選的年化成本可能低於主推。",
      "「流動性最佳」依 OI 由高到低挑選，不套用以上條件。"
    ]
  end

  # 排行表徽章：近／遠天期「最划算」的主推＝最優、次選＝次選。
  def best_value_badge_for(row)
    @best_value_badges ||= %i[near_term far_term].each_with_object({}) do |term, acc|
      group = best_value_group(term)
      next if group.nil?

      acc[badge_key(group[:pick])] = "最優"
      acc[badge_key(group[:runner_up])] ||= "次選" if group[:runner_up]
    end
    @best_value_badges[badge_key(row)]
  end

  def badge_key(row) = [ row[:expiration_date].to_s, row[:strike].to_f ]

  def annual_cost_pct_for(row) = LeapsBestValueService.metrics(row)&.dig(:annual_cost_pct)
end
