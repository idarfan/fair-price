# frozen_string_literal: true

class IvWatchlists::IndexView::SymbolRow < ApplicationComponent
  def initialize(item:)
    @item = item
  end

  def view_template
    div(id: "watchlist-row-#{@item.id}", class: "border-b border-gray-800 last:border-0") do
      div(
        class: "flex items-center justify-between px-5 py-3 hover:bg-gray-800/50 transition-colors cursor-pointer select-none",
        data:  { action: "click->iv-chart#toggle", symbol: @item.symbol, row_id: @item.id }
      ) do
        div(class: "flex items-center gap-3") do
          span(class: "text-gray-500 text-xs transition-transform duration-200", data: { iv_chart_target: "arrow-#{@item.id}" }) { "▶" }
          span(class: "text-white font-mono font-medium text-sm") { @item.symbol }
          span(class: "text-gray-500 text-xs") { "加入於 #{@item.created_at.strftime('%Y/%m/%d')}" }
        end
        div(class: "flex items-center gap-3") do
          button(
            type: "button",
            class: "relative w-9 h-5 rounded-full transition-colors #{@item.active? ? 'bg-green-600' : 'bg-gray-600'}",
            data:  { action: "click->watchlist#toggle:stop", url: "/iv_watchlists/#{@item.id}/toggle", id: @item.id },
            title: @item.active? ? "點擊停用" : "點擊啟用"
          ) do
            span(class: "absolute top-1 w-3 h-3 bg-white rounded-full transition-all #{@item.active? ? 'left-5' : 'left-1'}")
          end
          button(
            type: "button",
            class: "text-gray-600 hover:text-red-400 transition-colors px-1",
            data:  { action: "click->watchlist#remove:stop", url: "/iv_watchlists/#{@item.id}", symbol: @item.symbol, id: @item.id },
            title: "移除 #{@item.symbol}"
          ) { "✕" }
        end
      end

      div(id: "chart-panel-#{@item.id}", class: "hidden px-5 pb-5 pt-2 bg-gray-950") do
        div(class: "flex gap-2 mb-3") do
          [7, 30, 60, 90, 180].each do |d|
            button(
              type: "button",
              class: "px-3 py-1 text-xs rounded border transition-colors #{d == 90 ? 'bg-blue-600 border-blue-500 text-white' : 'bg-gray-800 border-gray-600 text-gray-400 hover:text-white'}",
              data:  { action: "click->iv-chart#changeDays", symbol: @item.symbol, days: d, row_id: @item.id }
            ) { "#{d}天" }
          end
        end
        div(class: "text-gray-500 text-sm text-center py-4 hidden", data: { iv_chart_target: "loading-#{@item.id}" }) { "載入中..." }
        div(id: "charts-wrap-#{@item.id}", class: "relative") do
          div(id: "ch-line-#{@item.id}", class: "absolute top-0 bottom-0 hidden pointer-events-none z-20",
              style: "width:0; border-left:1px dashed rgba(255,255,255,0.4);")
          div(class: "relative", style: "height:280px") { canvas(id: "chart-iv-#{@item.id}") }
          div(class: "relative mt-3", style: "height:120px") { canvas(id: "chart-skew-#{@item.id}") }
        end
        div(class: "flex gap-4 mt-2 text-xs text-gray-500") do
          span { "🔴 Put IV" }
          span { "🟢 Call IV" }
          span { "🟡 股價（右軸）" }
          span { "🟣 Skew > 75th pct = 恐慌區" }
        end

        div(class: "mt-4 bg-gray-900 border border-gray-700/50 rounded-lg px-4 py-3") do
          p(class: "text-xs font-medium text-gray-400 mb-2") { "📖 底部訊號閱讀順序" }
          div(class: "space-y-1.5 text-xs text-gray-500") do
            div(class: "flex items-start gap-2") do
              span(class: "text-gray-600 font-mono flex-shrink-0") { "1." }
              span { "📉 黃虛線（股價）持續往下" }
            end
            div(class: "flex items-start gap-2") do
              span(class: "text-gray-600 font-mono flex-shrink-0") { "2." }
              span { "🔵→🩷 柱子從藍色變桃紅色 → 進入警戒，不要動作" }
            end
            div(class: "flex items-start gap-2") do
              span(class: "text-gray-600 font-mono flex-shrink-0") { "3." }
              span { "⏳ 桃紅色持續 2～3 根 → 恐慌累積期，繼續觀望" }
            end
            div(class: "flex items-start gap-2") do
              span(class: "text-green-500 font-mono flex-shrink-0") { "4." }
              span(class: "text-green-400 font-medium") { "📏 下一根桃紅柱明顯縮短 ← 底部訊號，恐慌釋放完畢，反彈即將來臨" }
            end
          end
        end
      end
    end
  end
end
