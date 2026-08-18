# frozen_string_literal: true

module LeapsRecommendations::PmccSection
  # PMCC v3 §9.1：12 個關鍵欄常駐顯示，其餘（Bid/Ask、Gamma/Theta/Vega/Moneyness/
  # Theoretical/ITM Prob/Vol/OI/Vol-OI/OI Chg、MaxProfit未收租、未年化收租率）
  # 放進每列的 details/summary 展開區。
  PMCC_TABLE_COLS = [
    "KL", "PL(mid)", "Long DTE", "Long Δ",
    "KS", "PS(mid)", "Short Δ",
    "Spread", "NetDebit", "MaxProfit(含SC)", "年化收租率",
    "Golden Rule"
  ].freeze


  # 使用者回報：PMCC 表格桶內排序只依 max_profit，不能依 KS 瀏覽——需求擴大為
  # LEAPS 排行表跟 PMCC 表都要能點表頭切換排序鍵。跟 TABLE_COL_KEYS 一樣一一對齊。
  PMCC_TABLE_COL_KEYS = %w[
    kl pl long_dte long_delta ks ps short_delta spread net_debit max_profit yield_ann passes
  ].freeze
  raise "PMCC_TABLE_COL_KEYS 與 PMCC_TABLE_COLS 長度不一致" unless PMCC_TABLE_COL_KEYS.size == PMCC_TABLE_COLS.size


  def render_pmcc_section
    return unless @pmcc_ranking

    status = @pmcc_ranking[:status]

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex justify-between items-center flex-wrap gap-2") do
        div do
          h2(class: "text-base font-semibold text-gray-700") { plain "⚖️ PMCC黃金法則組合 — #{@symbol}" }
          p(class: "text-xs text-gray-500 mt-0.5") { plain "PL < KS−KL · 每到期日前 5" }
        end
        if status == :ok
          summary = @pmcc_ranking[:summary]
          div(class: "text-sm font-medium whitespace-nowrap") do
            plain "總組合 #{summary[:total_combos]} / 通過 #{summary[:passing_combos]}"
          end
        end
      end

      case status
      when :no_leaps, :no_short, :no_data
        div(class: "px-4 py-6 text-center text-sm text-gray-400") { plain "尚無 Short Call 資料，請重新查詢" }
      when :ok
        # data-sort-scope 包住三個到期日桶，一排 toggle 同時控制底下全部
        # table[data-sortable]（不是每桶各自一排——使用者要求共用一份）。
        div(data_sort_scope: "true") do
          render_pmcc_sort_toggles
          div(class: "divide-y divide-gray-100") do
            @pmcc_ranking[:summary][:expirations].each_with_index do |exp_key, idx|
              render_pmcc_bucket(exp_key, @pmcc_ranking[exp_key], idx)
            end
          end
        end
      end
    end
  end


  PMCC_TERM_LABELS = [ "近月", "中月", "遠月" ].freeze


  def render_pmcc_bucket(exp_key, bucket, idx)
    div(class: "px-4 py-4") do
      div(class: "flex items-center gap-2 flex-wrap mb-2") do
        h3(class: "text-sm font-semibold text-gray-700") do
          plain "#{bucket[:expiration]} · #{bucket[:short_dte]} DTE"
        end
        term = PMCC_TERM_LABELS[idx]
        span(class: "text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-500") { plain term } if term
        if bucket[:short_dte].to_i.positive? && bucket[:short_dte].to_i < 19
          span(class: "text-xs px-2 py-0.5 rounded-full bg-orange-50 text-orange-800 border border-orange-300") do
            plain "⚠️ 短於 lesson9 建議區間（19–45 天）：Gamma 風險高、被指派機率陡增、收租金額低"
          end
        end
      end

      if bucket[:combos].empty?
        div(class: "text-xs text-gray-400 py-2") { plain "此到期日無 KS>KL 組合" }
      else
        render_pmcc_table(bucket[:combos])
      end
    end
  end


  def render_pmcc_table(combos)
    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs text-gray-700", data_sortable: "true") do
        thead(class: "bg-gray-50 text-gray-500 text-xs") do
          tr do
            PMCC_TABLE_COLS.each_with_index do |col, idx|
              # data-tip-key 用 pmcc_ 前綴跟 LEAPS 表既有的 tip key（spread 等）分開，
              # 兩邊「Spread」意義不同（PMCC 是 KS−KL 價差，LEAPS 是 Bid-Ask Spread%）。
              # 這裡沒有 id——PMCC 表格每個到期日桶各渲染一次，同一個 key 的 th 在
              # 頁面上出現三次，用 id 會重複；hover tip 靠 data-tip-key 委派即可，
              # 不需要唯一 id，見 render_tooltips_script。
              th(data_tip_key: "pmcc_#{PMCC_TABLE_COL_KEYS[idx]}",
                 class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain col }
            end
            th(class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain "詳細" }
          end
        end
        tbody do
          combos.each_with_index { |combo, i| render_pmcc_combo_row(combo, i) }
        end
      end
    end
  end


  # 使用者回報：每欄都能點排序太多餘、下拉選單也不要，要一排互斥的 toggle
  # 開關（截圖範例：一個欄位一個開關，開哪個就依那欄排序，同時只能開一個）。
  # 一個容器 data-sort-scope 內放 toggle 列 + 表格，JS 用 closest 從被點的
  # toggle 找到同一個 scope 裡的 table[data-sortable]。
  def render_pmcc_sort_toggles
    div(class: "flex flex-wrap items-center gap-1.5 px-1 pb-2") do
      PMCC_TABLE_COLS.each_with_index do |col, idx|
        key = PMCC_TABLE_COL_KEYS[idx]
        button(type: "button", data_sort_key: key,
               class: "sort-toggle flex items-center gap-1 px-1.5 py-1 rounded-full border " \
                      "border-gray-200 bg-white text-[10px] text-gray-500 hover:border-blue-300 transition-colors") do
          span(class: "sort-toggle-track relative inline-block w-6 h-3.5 rounded-full bg-gray-300 transition-colors flex-shrink-0") do
            span(class: "sort-toggle-knob absolute top-0.5 left-0.5 w-2.5 h-2.5 rounded-full bg-white shadow transition-transform")
          end
          span(class: "sort-toggle-arrow w-2.5 text-gray-400 text-[9px]") { plain "" }
          span(class: "whitespace-nowrap") { plain col }
        end
      end
    end
  end


  def render_pmcc_combo_row(combo, i)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    fail_row  = !combo[:passes_golden_rule]
    row_bg    = fail_row ? "bg-red-50" : (i.odd? ? "bg-gray-50/50" : "")

    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{row_bg}",
       data_sort_json: pmcc_combo_sort_json(combo)) do
      td(class: "px-3 py-2 text-center font-semibold text-blue-600") { plain fmt_price(long_leg[:strike]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(long_leg[:mid]) }
      td(class: "px-3 py-2 text-center")                             { plain long_leg[:dte].to_s }
      td(class: "px-3 py-2 text-center")                             { render_pmcc_delta_cell(long_leg[:delta], combo[:leaps_delta_ok]) }
      td(class: "px-3 py-2 text-center font-semibold text-red-600")  { plain fmt_price(short_leg[:strike]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(short_leg[:mid]) }
      td(class: "px-3 py-2 text-center")                             { render_pmcc_delta_cell(short_leg[:delta], combo[:short_delta_ok]) }
      td(class: "px-3 py-2 text-center #{pmcc_signed_color(combo[:spread])}")     { plain fmt_price(combo[:spread]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(combo[:net_debit]) }
      td(class: "px-3 py-2 text-center font-semibold #{pmcc_signed_color(combo[:max_profit])}") { plain fmt_price(combo[:max_profit]) }
      td(class: "px-3 py-2 text-center font-semibold")               { plain fmt_pmcc_pct(combo[:premium_yield_ann]) }
      td(class: "px-3 py-2 text-center") { render_pmcc_verdict_cell(combo) }
      td(class: "px-3 py-2 text-center") { render_pmcc_details_cell(combo) }
    end
  end


  def render_pmcc_delta_cell(delta, ok)
    span(class: ok ? "text-green-700 font-semibold" : "text-gray-600") do
      plain fmt_decimal(delta, 3)
      plain " ✅" if ok
    end
  end


  def render_pmcc_verdict_cell(combo)
    if combo[:passes_golden_rule]
      span(class: "text-green-700 font-semibold whitespace-nowrap") { plain "✅ 通過" }
    else
      div(class: "flex flex-col items-center gap-0.5 max-w-[160px]") do
        span(class: "text-red-700 font-semibold") { plain "❌" }
        span(class: "text-red-500 text-[10px] leading-tight whitespace-normal") { plain combo[:fail_reason] }
      end
    end
  end


  def render_pmcc_details_cell(combo)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    td_class  = "px-3 py-2 text-center"

    details(class: "inline-block text-left") do
      summary(class: "cursor-pointer text-blue-500 text-xs list-none") { plain "展開 ▾" }
      div(class: "mt-2 text-left text-[11px] text-gray-500 space-y-0.5 whitespace-nowrap") do
        p { plain "Long Bid/Ask #{fmt_price(long_leg[:bid])}/#{fmt_price(long_leg[:ask])}　OI #{fmt_int(long_leg[:oi])}" }
        p { plain "Long 內在/外在 #{fmt_price(long_leg[:intrinsic])}/#{fmt_price(long_leg[:extrinsic])}" }
        p { plain "Short Bid/Ask #{fmt_price(short_leg[:bid])}/#{fmt_price(short_leg[:ask])}　Theo #{fmt_price(short_leg[:theoretical_price])}" }
        p { plain "Short Moneyness #{fmt_pct(short_leg[:moneyness])}" }
        p do
          plain "Gamma #{fmt_decimal(short_leg[:gamma], 4)}"
          if short_leg[:gamma].to_f > 0.20
            span(class: "text-orange-600") { plain " ⚠️" }
          end
        end
        p { plain "Theta #{fmt_decimal(short_leg[:theta], 4)}　Vega #{fmt_decimal(short_leg[:vega], 4)}" }
        p { plain "IV #{fmt_pct(short_leg[:iv])}　ITM Prob #{fmt_pct(short_leg[:itm_probability])}" }
        p { plain "Vol #{fmt_int(short_leg[:vol])}　OI #{fmt_int(short_leg[:oi])}　Vol/OI #{fmt_decimal(short_leg[:vol_oi_ratio], 3)}　OI Chg #{fmt_int(short_leg[:oi_change])}" }
        p { plain "MaxProfit(未收租) #{fmt_price(combo[:max_profit_no_sc])}　收租率(未年化) #{fmt_pmcc_pct(combo[:premium_yield])}" }
      end
    end
  end


  # 每個 key 對應 TABLE_COL_KEYS 同名欄位，供前端 JS 依 data-sort-key 做數值排序。
  # liquidity 不是天然數值，借用 LeapsRecommendationService::TIER_ORDER 轉成排序用等第。
  # 每個 key 對應 PMCC_TABLE_COL_KEYS 同名欄位。passes（Golden Rule）借用 1/0 排序，
  # 讓使用者也能點「Golden Rule」欄把通過的組合集中在最上面或最下面。
  def pmcc_combo_sort_json(combo)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    {
      kl:          long_leg[:strike]&.to_f,
      pl:          long_leg[:mid]&.to_f,
      long_dte:    long_leg[:dte],
      long_delta:  long_leg[:delta]&.to_f,
      ks:          short_leg[:strike]&.to_f,
      ps:          short_leg[:mid]&.to_f,
      short_delta: short_leg[:delta]&.to_f,
      spread:      combo[:spread]&.to_f,
      net_debit:   combo[:net_debit]&.to_f,
      max_profit:  combo[:max_profit]&.to_f,
      yield_ann:   combo[:premium_yield_ann]&.to_f,
      passes:      combo[:passes_golden_rule] ? 1 : 0
    }.to_json
  end

  # ── Formatters ──────────────────────────────────────────────────────────────
end
