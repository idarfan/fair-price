# frozen_string_literal: true

# pmcc-tracker Phase 5：部位追蹤區塊。
#
# 垂直堆疊在 pmcc_section（黃金法則排行表）下方，不並排——並排會讓版面壅擠。
# 預設**收摺**，只顯示摘要列；沿用 pmcc_section 那套原生 details/summary
# （`.leaps-pmcc-bucket`），零 JS，也避開 Phlex 2.x 封鎖 on* 屬性。
#
# 無部位時整個區塊不渲染，不顯示空的收折列。
module LeapsRecommendations::PmccPositionTracker
  def render_pmcc_position_tracker
    return if @pmcc_tracker.blank?

    position = @pmcc_tracker[:position]
    pnl      = @pmcc_tracker[:pnl]

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      details(class: "leaps-pmcc-bucket") do
        summary(class: "flex items-center gap-2 flex-wrap cursor-pointer select-none") do
          h2(class: "text-sm font-semibold text-gray-700") do
            plain "PMCC 部位追蹤 — #{position.ticker}"
          end
          render_tracker_summary_badges(position, pnl)
        end

        div(class: "mt-3 space-y-4") do
          render_tracker_long_leg(pnl)
          render_tracker_short_leg(position)
          render_tracker_trigger
          render_tracker_suggestions
          render_tracker_timeline(pnl)
        end
      end
    end
  end


  # 收起來時也要看得出重點：長腳、目前短腳、累積損益
  def render_tracker_summary_badges(position, pnl)
    open_leg = position.open_short_leg

    span(class: "text-xs text-gray-500") do
      plain "KL #{fmt_strike_short(position.long_strike)}"
      plain " / KS #{fmt_strike_short(open_leg.short_strike)}" if open_leg
    end
    span(class: "text-xs #{pmcc_signed_color(pnl[:realized])}") do
      plain "已實現 #{fmt_signed_money(pnl[:realized])}"
    end
    if pnl[:total]
      span(class: "text-xs #{pmcc_signed_color(pnl[:total])}") do
        plain "總損益 #{fmt_signed_money(pnl[:total])}"
      end
    end
  end


  # 實付成本與目前市價**分開標示**：計算一律用實付成本，市價只是顯示。
  # 混在一起會讓使用者分不清哪個數字進了帳本。
  def render_tracker_long_leg(pnl)
    leg = pnl[:long_leg]

    div(class: "px-1") do
      h3(class: "text-xs font-semibold text-gray-600 mb-1") { plain "長腳（LEAPS）" }
      div(class: "flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600") do
        plain_stat("履約價", fmt_price(leg[:strike]))
        plain_stat("到期日", leg[:expiration].to_s)
        plain_stat("口數", leg[:contracts].to_s)
        plain_stat("實付成本", fmt_price(leg[:entry_cost]))
        if leg[:market_mid]
          plain_stat("目前市價", fmt_price(leg[:market_mid]))
          span(class: pmcc_signed_color(pnl[:unrealized])) do
            plain "未實現 #{fmt_signed_money(pnl[:unrealized])}"
          end
          span(class: "text-gray-400") { plain "（報價 #{leg[:quoted_at]&.strftime('%m-%d %H:%M')}）" }
        else
          span(class: "text-orange-600") { plain "⚠ 尚無長腳報價，未實現損益無法計算" }
        end
      end
    end
  end


  def render_tracker_short_leg(position)
    leg = position.open_short_leg

    div(class: "px-1") do
      h3(class: "text-xs font-semibold text-gray-600 mb-1") { plain "目前短腳" }
      if leg.blank?
        div(class: "text-xs text-gray-400") { plain "目前沒有未平倉的短腳" }
      else
        div(class: "flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600") do
          plain_stat("履約價", fmt_price(leg.short_strike))
          plain_stat("到期日", leg.short_expiration.to_s)
          plain_stat("口數", leg.contracts.to_s)
          plain_stat("收租", fmt_price(leg.premium_collected))
        end
      end
    end
  end


  # 觸發判斷只提示、不自動執行——同本專案「不自動下結論」的原則
  def render_tracker_trigger
    trigger = @pmcc_tracker[:trigger]
    return if trigger.blank?

    div(class: "px-1") do
      h3(class: "text-xs font-semibold text-gray-600 mb-1") { plain "滾倉判斷" }
      if trigger[:error] == :no_quote
        div(class: "text-xs text-orange-600") { plain "⚠ 短腳報價缺失，無法判斷（不是「不需滾倉」）" }
      elsif trigger[:should_roll]
        div(class: "space-y-1") do
          trigger[:reasons].each do |reason|
            div(class: "text-xs px-2 py-1 rounded bg-orange-50 text-orange-800 border border-orange-200") do
              plain "⚠ #{reason.message}"
            end
          end
        end
      else
        div(class: "text-xs text-green-700") { plain "✅ 目前不需滾倉" }
      end
    end
  end


  def render_tracker_suggestions
    result = @pmcc_tracker[:suggestions]
    return if result.blank?

    div(class: "px-1") do
      h3(class: "text-xs font-semibold text-gray-600 mb-1") { plain "滾倉候選" }
      case result[:status]
      when :no_open_leg      then render_tracker_note("目前沒有未平倉的短腳，無需滾倉")
      when :no_buyback_quote then render_tracker_note("缺少目前短腳的報價，算不出滾動淨現金流")
      when :no_candidates    then render_tracker_note("沒有符合條件的滾倉候選（僅往上滾、Delta 0.15–0.30）")
      else render_tracker_suggestion_table(result[:suggestions])
      end
    end
  end


  TRACKER_COLS = [ "履約價", "到期日", "DTE", "Delta", "權利金", "Spread",
                   "滾動現金流", "NetDebit", "MaxProfit", "黃金法則" ].freeze


  def render_tracker_suggestion_table(rows)
    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs text-gray-700") do
        thead(class: "bg-gray-50 text-gray-500") do
          tr do
            TRACKER_COLS.each do |col|
              th(class: "px-2 py-1.5 text-center font-medium whitespace-nowrap") { plain col }
            end
          end
        end
        tbody do
          rows.each_with_index { |row, i| render_tracker_suggestion_row(row, i) }
        end
      end
    end
  end


  def render_tracker_suggestion_row(row, index)
    tr(class: "border-t border-gray-100 #{row[:passes_golden_rule] ? (index.odd? ? 'bg-gray-50/50' : '') : 'bg-red-50'}") do
      td(class: "px-2 py-1.5 text-center font-semibold") { plain fmt_price(row[:strike]) }
      td(class: "px-2 py-1.5 text-center font-mono whitespace-nowrap") { plain row[:expiration].to_s }
      td(class: "px-2 py-1.5 text-center") do
        plain row[:dte].to_s
        unless row[:in_suggested_dte]
          span(class: "ml-1 text-orange-600") { plain "⚠" }
        end
      end
      td(class: "px-2 py-1.5 text-center") { plain fmt_decimal(row[:delta], 3) }
      td(class: "px-2 py-1.5 text-center") { plain fmt_price(row[:mid]) }
      td(class: "px-2 py-1.5 text-center") { plain fmt_price(row[:spread]) }
      td(class: "px-2 py-1.5 text-center #{pmcc_signed_color(row[:roll_cash_flow])}") { plain fmt_price(row[:roll_cash_flow]) }
      td(class: "px-2 py-1.5 text-center") { plain fmt_price(row[:net_debit]) }
      td(class: "px-2 py-1.5 text-center font-semibold #{pmcc_signed_color(row[:max_profit])}") { plain fmt_price(row[:max_profit]) }
      td(class: "px-2 py-1.5 text-center") do
        if row[:passes_golden_rule]
          span(class: "text-green-700") { plain "✅ 通過" }
        else
          span(class: "text-red-700", title: row[:fail_reason].to_s) { plain "❌ #{row[:fail_reason]}" }
        end
      end
    end
  end


  def render_tracker_timeline(pnl)
    events = pnl[:timeline]

    div(class: "px-1") do
      h3(class: "text-xs font-semibold text-gray-600 mb-1") { plain "損益帳本" }
      if events.empty?
        render_tracker_note("尚無已實現事件")
      else
        div(class: "space-y-1") do
          events.each { |e| render_tracker_timeline_row(e) }
        end
        div(class: "text-xs text-gray-500 pt-1 border-t border-gray-100 mt-1") do
          plain "累積已實現 #{fmt_signed_money(pnl[:realized])}"
          if pnl[:annualized_return]
            plain "　年化 #{fmt_pct(pnl[:annualized_return])}（持有 #{pnl[:holding_days]} 天）"
          end
        end
      end
    end
  end


  TRACKER_EVENT_LABELS = {
    "short_expired"  => "短腳到期歸零",
    "short_closed"   => "短腳買回平倉",
    "short_assigned" => "短腳被指派",
    "long_exercised" => "長腳行權",
    "long_closed"    => "長腳平倉"
  }.freeze


  def render_tracker_timeline_row(event)
    div(class: "flex items-center gap-2 text-xs") do
      span(class: "text-gray-400 font-mono whitespace-nowrap") do
        plain event[:occurred_at]&.strftime("%Y-%m-%d").to_s
      end
      span(class: "text-gray-600") { plain TRACKER_EVENT_LABELS[event[:event_type]] || event[:event_type] }
      span(class: pmcc_signed_color(event[:realized_pnl])) { plain fmt_signed_money(event[:realized_pnl]) }
      if event[:fees].to_f.positive?
        span(class: "text-gray-400") { plain "（含手續費 #{fmt_price(event[:fees])}）" }
      end
    end
  end


  def render_tracker_note(text)
    div(class: "text-xs text-gray-400") { plain text }
  end


  def plain_stat(label, value)
    span do
      span(class: "text-gray-400") { plain "#{label} " }
      plain value
    end
  end


  # 金額帶正負號，讓損益一眼可辨
  def fmt_signed_money(val)
    return "—" if val.nil?

    sprintf("%+.2f", val.to_f)
  end
end
