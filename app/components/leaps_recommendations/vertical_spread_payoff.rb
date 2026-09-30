# frozen_string_literal: true

# LEAPS 垂直價差「預估股價」的結果片段（leaps-call-spread-spec P7；tasks/leaps-vertical-fix.md S3 第 4、10 點）。
#
# 區塊內第一次渲染時是空的；前端（leapsVerticalSpread.ts）在使用者輸入後向
# GET /leaps/vertical_spread?payoff=1 取回這個元件的 HTML，換掉 [data-vs-payoff-result] 的內容。
# result：LeapsVerticalSpreadService::Payoff.call 的回傳值（nil／{ error: }／計算結果）。
class LeapsRecommendations::VerticalSpreadPayoff < ApplicationComponent
  TONE_CLASS = { profit: "vs-tone-profit", breakeven: "vs-tone-breakeven", loss: "vs-tone-loss" }.freeze
  EARLY_ASSIGNMENT = "賣出腳為價內且標的有配息，到期前可能在除息前被提前指派"

  def initialize(result:)
    @result = result
  end

  def view_template
    return if @result.nil?
    return span(class: "vs-tone-loss") { plain @result[:error] } if @result[:error]

    span(data_vs_payoff_line: "true") do
      plain "→ "
      render_close(@result[:close])
      plain "｜到期損益 "
      render_expiry(@result[:expiry])
    end
    return unless @result.dig(:flags, :early_assignment_risk)

    span(class: "block mt-1 text-xs text-yellow-800", data_vs_flag: "early_assignment_risk") { plain EARLY_ASSIGNMENT }
  end

  private

  def render_close(close)
    return span(class: "vs-tone-loss") { plain close[:error] } if close[:error]

    plain "平倉理論損益 "
    span(class: "#{TONE_CLASS.fetch(close[:tone])} font-semibold", data_vs_close_pnl: "true") { plain close[:display][:pnl] }
    plain "（保守 #{close[:display][:conservative]}）"
  end

  def render_expiry(expiry)
    display = expiry[:display]
    span(class: "#{TONE_CLASS.fetch(expiry[:tone])} font-semibold", data_vs_expiry_pnl: "true") { plain display[:pnl] }
    plain "（#{display[:pct]}）"
  end
end
