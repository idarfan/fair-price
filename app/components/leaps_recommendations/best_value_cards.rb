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
      render_contract_block(pick, primary: true)
      render_contract_block(group[:runner_up], primary: false) if group[:runner_up]
    end
  end

  # 右卡的欄位列表（主推＋次選）：既有 OI 推薦內容不動，只在下方補同一組欄位。
  def render_oi_metric_blocks(group)
    render_contract_block(group[:pick], primary: true, badge: false)
    render_contract_block(group[:runner_up], primary: false) if group[:runner_up]
  end

  # 一筆合約：標題列（主推／次選＋履約價／到期日）＋八個欄位。
  def render_contract_block(row, primary:, badge: true)
    div(class: "mt-2 first:mt-0") do
      if badge || !primary
        div(class: "flex flex-wrap items-center gap-2 mb-1") do
          span(class: "text-[10px] text-gray-500") { plain primary ? "主推" : "次選" }
          span(class: "text-xs font-semibold text-gray-800") { plain contract_label(row) }
          if row[:no_recent_volume_warning]
            span(class: "text-orange-600 text-xs whitespace-nowrap", title: THIN_TRADING_TOOLTIP) { plain THIN_TRADING_LABEL }
          end
        end
      end
      render_metric_list(row)
    end
  end

  # 最划算卡的列是 LeapsBestValueService 回傳值，指標已算好（且不帶 underlying_price）；
  # OI 卡的列是排行候選，沒有指標，用同一支公式補算。
  def render_metric_list(row)
    metrics = row.key?(:annual_cost_pct) ? row : (LeapsBestValueService.metrics(row) || {})
    dl(class: "grid grid-cols-2 sm:grid-cols-4 gap-x-3 gap-y-1 text-xs", data_leaps_metric_list: "") do
      metric_items(row, metrics).each_with_index do |(label, value), i|
        # 「履約價／到期日」的值最長（$130.00 / 2028-01-21），獨佔一整行，否則會壓到右邊欄位。
        span_class = i.zero? ? " col-span-2 sm:col-span-4" : ""
        div(class: "flex justify-between gap-2 min-w-0#{span_class}") do
          dt(class: "text-gray-400 whitespace-nowrap") { plain label }
          dd(class: "text-gray-800 font-mono tabular-nums whitespace-nowrap") { plain value }
        end
      end
    end
  end

  def metric_items(row, metrics)
    [
      [ "履約價／到期日", contract_label(row) ],
      [ "Delta",        fmt_decimal(row[:delta], 3) ],
      [ "Ask",          fmt_price(row[:ask]) ],
      [ "OI",           fmt_int(row[:open_interest]) ],
      [ "成交量",       fmt_int(row[:volume]) ],
      [ "Spread %",     fmt_cost_pct(metrics[:spread_pct]) ],
      [ "年化時間成本", fmt_cost_pct(metrics[:annual_cost_pct]) ],
      [ "損益兩平",     fmt_cost_pct(metrics[:breakeven_pct]) ]
    ]
  end

  # 已經是百分比數值（7.36 → "7.36%"），跟既有 fmt_pct（小數 ×100）不同，所以另開一支。
  def fmt_cost_pct(value) = value.nil? ? "—" : sprintf("%.2f%%", value)

  def contract_label(row) = "#{sprintf('$%.2f', row[:strike].to_f)} / #{row[:expiration_date]}"

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
