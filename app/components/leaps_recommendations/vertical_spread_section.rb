# frozen_string_literal: true

# LEAPS 垂直價差區塊的內容（leaps-call-spread-spec P3／P4）。
#
# /leaps 頁面先以 :loading 狀態放進 VerticalSpreadFrame 外框；前端 behavior
# （leapsVerticalSpread.ts）再向 GET /leaps/vertical_spread 取回同一個元件的
# 結果／錯誤／讀取失敗狀態，替換外框內容。數字全部來自 LeapsVerticalSpreadService，
# 這裡不做任何計算。CSP 不允許 inline style，一律用 class。
class LeapsRecommendations::VerticalSpreadSection < ApplicationComponent
  TITLE = "LEAPS 垂直價差"
  NOTE = "需 Firstrade 選擇權 Level 3；請用價差單一次成交兩腳。最大獲利要到到期日才完整實現。"
  AFTER_HOURS_BADGE = "盤後參考價：以最後成交價計算，實際成交價可能不同"
  RESULT_ROWS = [
    [ :net_cost, "實付淨成本" ], [ :max_profit, "最大獲利" ], [ :breakeven, "損益兩平" ],
    [ :max_loss, "最大虧損" ], [ :risk_reward, "風險報酬比" ], [ :width, "價差寬度" ]
  ].freeze
  SELECT_CLASS = "w-full px-3 py-2 rounded-lg border border-gray-300 text-sm bg-white " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500"
  ERROR_CLASS = "px-4 py-3 rounded-lg text-sm bg-red-50 border border-red-300 text-red-800"

  # outcome：LeapsVerticalSpreadService#call 的回傳值。state：:loading／:cdp_offline 時不看 outcome。
  def initialize(symbol:, user_strike:, outcome: nil, state: nil, message: nil)
    @symbol = symbol
    @user_strike = user_strike
    @outcome = outcome || {}
    @state = state
    @message = message
  end

  def view_template
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden", data_vs_section: "true") do
      render_header
      div(class: "p-4 space-y-4") { render_body }
    end
  end

  private

  def render_header
    div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex justify-between items-center flex-wrap gap-2") do
      h2(class: "text-base font-semibold text-gray-700") { plain "#{TITLE} — #{@symbol}" }
      if (quoted_at = @outcome[:quoted_at])
        span(class: "text-xs text-gray-500") do
          plain "報價時間：#{quoted_at.in_time_zone('Asia/Taipei').strftime('%Y-%m-%d %H:%M')}（台北時間）"
        end
      end
    end
  end

  def render_body
    case @state
    when :loading     then render_loading
    when :cdp_offline then render_failure(@message)
    else render_outcome
    end
  end

  def render_loading
    div(class: "space-y-2", data_vs_progress: "true") do
      div(class: "h-2 w-full rounded-full bg-gray-100 overflow-hidden") do
        div(class: "h-2 w-1/3 rounded-full bg-blue-500 animate-pulse")
      end
      p(class: "text-sm text-gray-500", data_vs_progress_text: "true") { plain "讀取 Barchart 報價中…" }
    end
  end

  def render_outcome
    error = @outcome[:error]
    return render_failure(error[:message]) if error && error[:kind] == :fetch_failed

    render_form if @outcome[:long_options].present?
    div(class: ERROR_CLASS) { plain error[:message] } if error
    render_result(@outcome[:result]) if @outcome[:result]
    p(class: "text-xs text-gray-500") { plain NOTE }
  end

  # 讀取失敗／CDP 離線：紅字加重試，不顯示任何計算數字。
  def render_failure(message)
    div(class: "#{ERROR_CLASS} flex items-center justify-between gap-3 flex-wrap") do
      span { plain message }
      button(type: "button", data_vs_retry: "true",
             class: "px-3 py-1 rounded-lg bg-red-600 text-white text-xs font-medium hover:bg-red-700") { plain "重試" }
    end
  end

  def render_form
    selected = @outcome[:selected] || {}
    form(method: "get", action: "/leaps/vertical_spread", data_vs_form: "true",
         class: "grid grid-cols-1 md:grid-cols-2 gap-3") do
      input(type: "hidden", name: "symbol", value: @symbol)
      input(type: "hidden", name: "user_strike", value: @user_strike)
      render_select("expiry", "買入腳（履約價固定 #{Format.num(@outcome[:long_strike])}）",
                    @outcome[:long_options], selected[:expiry]) { |o| o[:expiry] }
      render_select("short_strike", "賣出腳（同到期日、價外）",
                    @outcome[:short_options] || [], selected[:short_strike]) { |o| Format.num(o[:strike]) }
    end
  end

  def render_select(name, label_text, options, selected_value)
    label(class: "block text-xs text-gray-500 space-y-1") do
      span { plain label_text }
      select(name: name, class: SELECT_CLASS) do
        options.each do |o|
          value = yield(o)
          option(value: value, selected: same_value?(value, selected_value), disabled: o[:disabled]) { plain o[:label] }
        end
      end
    end
  end

  def same_value?(value, selected_value)
    return false if selected_value.nil?

    selected_value.is_a?(BigDecimal) ? value == Format.num(selected_value) : value == selected_value
  end

  def render_result(result)
    display = result[:display]
    if result[:after_hours_legs].any?
      div(class: "px-3 py-2 rounded-lg text-xs bg-yellow-50 border border-yellow-300 text-yellow-800") do
        plain "#{AFTER_HOURS_BADGE}（#{result[:after_hours_legs].map { |leg| leg == :long ? '買入腳' : '賣出腳' }.join('、')}）"
      end
    end

    div(class: "grid grid-cols-2 md:grid-cols-3 gap-3") do
      RESULT_ROWS.each do |key, label_text|
        div(class: "rounded-lg border border-gray-200 px-3 py-2") do
          p(class: "text-xs text-gray-500") { plain label_text }
          p(class: "text-lg font-semibold text-gray-800") { plain display[key] }
          p(class: "text-xs text-gray-400") { plain "保守成交 #{display[:net_cost_nat]}" } if key == :net_cost
        end
      end
    end
  end

  Format = LeapsVerticalSpreadService::Format
end
