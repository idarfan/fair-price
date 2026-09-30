# frozen_string_literal: true

# LEAPS 垂直價差「預估股價」輸入列（leaps-call-spread-spec P7；tasks/leaps-vertical-fix.md S3 第 3～5-b、7、11 點）。
#
# 預估股價、平倉日、IV 調整三個輸入欄；前端（leapsVerticalSpread.ts）在輸入後帶 data-vs-payoff-params
# 與三欄的值向 GET /leaps/vertical_spread?payoff=1 取回 VerticalSpreadPayoff 片段，填進 [data-vs-payoff-result]。
# 參數是 service 算好的 BigDecimal 原值（LeapsVerticalSpreadService#payoff_params），這裡不做任何計算。
class LeapsRecommendations::VerticalSpreadPayoffRow < ApplicationComponent
  CLOSE_OUT_TIP = "理論值：以報價時兩腳中間價反推 IV，並假設各履約價的 IV 維持不變。股價大幅變動時 IV skew 會移動，" \
                  "實際平倉價可能與理論值有偏差，可用 IV 調整欄做情境測試。實際成交以買賣價為準。"
  EXPIRY_HINT = "到期時若股價介於兩履約價之間，買入腳會自動履約、需付款買股；建議到期前平倉"
  INPUT_CLASS = "px-3 py-1.5 rounded-lg border border-gray-300 text-sm text-right " \
                "focus:outline-none focus:ring-2 focus:ring-blue-500"

  # result：LeapsVerticalSpreadService 的 result（payoff_params、close_out_error）。
  def initialize(result:)
    @result = result
  end

  def view_template
    params = @result[:payoff_params] || {}
    div(class: "space-y-2 text-sm", data_vs_payoff: "true", data_vs_payoff_params: params.to_json) do
      div(class: "flex items-center justify-center gap-3 flex-wrap", data_vs_payoff_inputs: "true") do
        render_target_price
        render_close_date(params)
        render_iv_shift
        span(class: "text-xs text-gray-500 cursor-help", title: CLOSE_OUT_TIP, data_vs_close_out_tip: "true") { plain "ⓘ" }
      end
      render_close_out_error if @result[:close_out_error]
      p(class: "text-center text-gray-700", data_vs_payoff_result: "true", aria_live: "polite")
      p(class: "text-center text-xs text-gray-500", data_vs_expiry_hint: "true") { plain EXPIRY_HINT }
    end
  end

  private

  def render_target_price
    label(for: "vs-target-price", class: "text-gray-600") { plain "到期日預估股價" }
    input(id: "vs-target-price", type: "number", min: "0", step: "0.01", inputmode: "decimal",
          data_vs_target_price: "true", class: "w-32 #{INPUT_CLASS}")
  end

  # 預設報價日、最早報價日、最晚到期日（S3 第 3 點）。
  def render_close_date(params)
    label(for: "vs-close-date", class: "text-gray-600") { plain "平倉日" }
    input(id: "vs-close-date", type: "date", value: params[:quote_date], min: params[:quote_date],
          max: params[:expiry], data_vs_close_date: "true", class: INPUT_CLASS)
  end

  # 單位百分點，兩腳同步加減（S3 第 5-b 點）。
  def render_iv_shift
    label(for: "vs-iv-shift", class: "text-gray-600") { plain "IV 調整（百分點）" }
    input(id: "vs-iv-shift", type: "number", value: "0", min: "-50", max: "50", step: "0.1",
          inputmode: "decimal", data_vs_iv_shift: "true", class: "w-24 #{INPUT_CLASS}")
  end

  def render_close_out_error
    p(class: "text-center text-xs vs-tone-loss", data_vs_close_out_error: "true") { plain @result[:close_out_error] }
  end
end
