# frozen_string_literal: true

module LeapsRecommendations::FlowPanel
  include LeapsRecommendations::SharedConstants

  FLOW_COLS = [ "類型", "履約價", "到期日", "DTE", "Delta", "Code", "Size", "Side", "Premium", "方向" ].freeze


  FLOW_COL_KEYS = %w[
    f_type f_strike f_expiration f_dte f_delta f_code f_size f_side f_premium f_direction
  ].freeze

  raise "FLOW_COL_KEYS 與 FLOW_COLS 長度不一致"   unless FLOW_COL_KEYS.size == FLOW_COLS.size


  def render_flow_panel
    return unless @flow_panel&.dig(:status) == :ok

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex justify-between items-center") do
        div do
          h2(class: "text-base font-semibold text-gray-700") { plain "Options Flow — 情緒參考，非排序依據" }
          p(class: "text-xs text-gray-500 mt-0.5") do
            plain "#{@flow_panel[:date]} · 前 20 大成交（依 Premium 降序）"
          end
        end
        div(class: "text-sm font-medium whitespace-nowrap pl-4") do
          span(class: "text-green-600") { plain "Call #{fmt_premium(@flow_panel[:call_premium_total])}" }
          span(class: "text-gray-400 mx-1") { plain "·" }
          span(class: "text-red-500") { plain "Put #{fmt_premium(@flow_panel[:put_premium_total])}" }
        end
      end

      render_highlighted if @flow_panel[:highlighted_trades]&.any?
      render_large_orders
    end
  end


  def render_highlighted
    div(class: "px-4 py-3 bg-blue-50 border-b border-blue-100") do
      p(class: "text-xs font-semibold text-blue-700 mb-1.5") { plain "排行候選 × 今日 Flow 重疊" }
      @flow_panel[:highlighted_trades].each do |hit|
        p(class: "text-xs text-blue-600") do
          plain "排行 ##{hit[:rank]} · $#{sprintf('%.2f', hit[:candidate_strike].to_f)} / " \
                "#{hit[:candidate_expiry]} — #{hit[:trades].size} 筆匹配"
        end
      end
    end
  end


  def render_large_orders
    orders = @flow_panel[:large_orders]
    return unless orders&.any?

    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs text-gray-700") do
        thead(class: "bg-gray-50 text-gray-500 text-xs") do
          tr do
            FLOW_COLS.each_with_index do |col, idx|
              key = FLOW_COL_KEYS[idx]
              th(id: "leaps-th-#{key}", data_tip_key: key, class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain col }
            end
          end
        end
        tbody do
          orders.each_with_index { |t, i| render_flow_row(t, i) }
        end
      end
    end
  end


  def render_flow_row(t, i = 0)
    dir   = (t[:direction] || "neutral").to_s
    ds    = DIR_STYLE[dir] || DIR_STYLE["neutral"]
    is_call = t[:option_type].to_s == "Call"
    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{i.odd? ? 'bg-gray-50/50' : ''}") do
      td(class: "px-3 py-2 text-center font-medium #{is_call ? 'text-green-700' : 'text-red-700'}") { plain t[:option_type].to_s }
      td(class: "px-3 py-2 text-center font-mono")              { plain fmt_price(t[:strike]) }
      td(class: "px-3 py-2 text-center font-mono text-xs")      { plain t[:expires_at].to_s }
      td(class: "px-3 py-2 text-center")                        { plain t[:dte].to_s }
      td(class: "px-3 py-2 text-center")                        { plain fmt_decimal(t[:delta], 3) }
      td(class: "px-3 py-2 text-center text-gray-500")          { plain t[:trade_condition].to_s }
      td(class: "px-3 py-2 text-center")                        { plain fmt_int(t[:size]) }
      td(class: "px-3 py-2 text-center")                        { plain t[:side].to_s }
      td(class: "px-3 py-2 text-center font-semibold")          { plain fmt_premium(t[:premium]) }
      td(class: "px-3 py-2 text-center") do
        div(class: "inline-flex items-center gap-1") do
          div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{ds[:dot]}")
          span(class: "#{ds[:text]}") { plain ds[:label] }
        end
      end
    end
  end

  # ── PMCC v3 §9.1: 黃金法則組合表 ──────────────────────────────────────────────
end
