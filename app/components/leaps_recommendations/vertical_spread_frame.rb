# frozen_string_literal: true

# /leaps 頁面上 LEAPS 垂直價差區塊的外框（leaps-call-spread-spec P3）。
#
# 只在同時輸入標的與價格時由 PageComponent 渲染。GET /leaps 不等 sidecar：
# 外框內先放 VerticalSpreadSection 的載入中狀態，前端 behavior 依 data-src
# 取回 /leaps/vertical_spread 的片段再替換內容（沿用專案的 data-behavior 慣例，
# 不用 Turbo，見規格附錄 A 決議 2）。
class LeapsRecommendations::VerticalSpreadFrame < ApplicationComponent
  def initialize(symbol:, user_strike:)
    @symbol = symbol
    @user_strike = user_strike
  end

  def view_template
    div(id: "leaps_vertical_spread", data_behavior: "leaps-vertical-spread", data_src: src) do
      render LeapsRecommendations::VerticalSpreadSection.new(symbol: @symbol, user_strike: @user_strike, state: :loading)
    end
  end

  private

  def src = "/leaps/vertical_spread?#{{ symbol: @symbol, user_strike: @user_strike }.to_query}"
end
