# frozen_string_literal: true

# ── 策略說明 ────────────────────────────────────────────
class IvWatchlists::IndexView::StrategyGuide < ApplicationComponent
  SIGNAL_STEPS = [
    { icon: "📉", label: "股價持續下跌", desc: "黃虛線（股價右軸）持續往下，市場進入恐慌模式" },
    { icon: "🔵→🩷", label: "柱子從藍色變桃紅色", desc: "Skew 飆升超過 75th pct，市場瘋狂買 Put 護盤，進入警戒區" },
    { icon: "⏳", label: "桃紅色持續 2～3 根", desc: "恐慌情緒累積期，繼續觀望，不要急著進場" },
    { icon: "📏", label: "下一根桃紅柱明顯縮短", desc: "← 底部訊號：Skew 開始收斂，恐慌釋放完畢，反彈即將來臨" },
  ].freeze

  WHEEL_ROWS = [
    { signal: "Skew 開始飆高（藍→桃紅）",      meaning: "QQQ 下跌中，SQQQ 上漲",           action: "不要新開 CSP，持倉觀望",         color: "text-yellow-400" },
    { signal: "Skew 持續桃紅 2～3 根",           meaning: "恐慌累積期",                       action: "繼續觀望，不動",                 color: "text-orange-400" },
    { signal: "桃紅後首根明顯縮短",              meaning: "底部訊號，QQQ 即將反彈，SQQQ 頂部臨近", action: "準備進場評估 SQQQ CSP",      color: "text-green-400" },
    { signal: "Skew 回落至藍色、收窄",           meaning: "QQQ 回升確認",                     action: "可重新開 SQQQ CSP 收 Premium", color: "text-blue-400" },
  ].freeze

  def view_template
    div(class: "mt-8 space-y-4") do
      render_signal_guide
      render_wheel_table
    end
  end

  private

  def render_signal_guide
    div(class: "bg-gray-900 border border-gray-700 rounded-xl p-6") do
      div(class: "flex items-center gap-2 mb-5") do
        span(class: "text-lg") { "📊" }
        h2(class: "text-sm font-semibold text-gray-200") { "Skew 底部訊號閱讀順序" }
        span(class: "text-xs text-gray-500 ml-2") { "（依序觀察 4 個步驟）" }
      end

      div(class: "space-y-3") do
        SIGNAL_STEPS.each_with_index do |step, i|
          div(class: "flex gap-4 items-start") do
            div(class: "flex flex-col items-center flex-shrink-0") do
              div(class: "w-7 h-7 rounded-full bg-gray-800 border border-gray-600 flex items-center justify-center text-xs font-bold text-gray-300") { (i + 1).to_s }
              div(class: "w-px h-4 bg-gray-700 mt-1") unless i == SIGNAL_STEPS.size - 1
            end
            div(class: "pb-2") do
              div(class: "flex items-center gap-2 mb-0.5") do
                span(class: "text-base") { step[:icon] }
                span(class: "#{ i == 3 ? 'text-green-300 font-semibold' : 'text-gray-200' } text-sm") { step[:label] }
              end
              p(class: "text-xs text-gray-500 leading-relaxed") { step[:desc] }
            end
          end
        end
      end
    end
  end

  def render_wheel_table
    div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
      div(class: "flex items-center gap-2 px-6 py-4 border-b border-gray-700") do
        span(class: "text-lg") { "🎡" }
        h2(class: "text-sm font-semibold text-gray-200") { "SQQQ Wheel 策略對照表" }
        span(class: "text-xs text-gray-500 ml-2") { "Put/Call Skew 訊號 → 操作含意" }
      end

      div(class: "overflow-x-auto") do
        table(class: "w-full text-xs") do
          thead do
            tr(class: "bg-gray-800/60") do
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "觀察到的現象" }
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "市場含意" }
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "操作含意" }
            end
          end
          tbody do
            WHEEL_ROWS.each_with_index do |row, i|
              tr(class: "border-t border-gray-800 #{ i == 2 ? 'bg-green-950/30' : '' }") do
                td(class: "px-5 py-3 text-gray-300 font-mono leading-relaxed") { row[:signal] }
                td(class: "px-5 py-3 text-gray-400 leading-relaxed") { row[:meaning] }
                td(class: "px-5 py-3 #{row[:color]} font-medium leading-relaxed") { row[:action] }
              end
            end
          end
        end
      end

      div(class: "px-6 py-3 bg-gray-800/40 border-t border-gray-700") do
        p(class: "text-xs text-gray-500") do
          plain("💡 CSP = Cash-Secured Put｜收 Premium 的前提是：Skew 已確認收斂，股價反彈開始。桃紅柱子期間不進場。")
        end
      end
    end
  end
end

