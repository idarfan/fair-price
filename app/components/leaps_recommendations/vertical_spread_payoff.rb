# frozen_string_literal: true

# LEAPS 垂直價差「到期日預估股價」的結果片段（leaps-call-spread-spec P7）。
#
# 區塊內第一次渲染時是空的；前端（leapsVerticalSpread.ts）在使用者輸入後向
# GET /leaps/vertical_spread?payoff=1 取回這個元件的 HTML，換掉 [data-vs-payoff-result] 的內容。
# result：LeapsVerticalSpreadService::Payoff.call 的回傳值（nil／{ error: }／計算結果）。
class LeapsRecommendations::VerticalSpreadPayoff < ApplicationComponent
  TONE_CLASS = { profit: "vs-tone-profit", breakeven: "vs-tone-breakeven", loss: "vs-tone-loss" }.freeze

  def initialize(result:)
    @result = result
  end

  def view_template
    return if @result.nil?
    return span(class: "vs-tone-loss") { plain @result[:error] } if @result[:error]

    display = @result[:display]
    plain "→ 到期損益 "
    span(class: "#{TONE_CLASS.fetch(@result[:tone])} font-semibold") { plain "#{display[:pnl]}（#{display[:pct]}）" }
  end
end
