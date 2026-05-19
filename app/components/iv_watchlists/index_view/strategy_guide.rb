# frozen_string_literal: true

# ── 策略說明 ────────────────────────────────────────────
class IvWatchlists::IndexView::StrategyGuide < ApplicationComponent
  SIGNAL_STEPS = [
    { icon: "📉", label: "股價持續下跌", desc: "黃虛線（股價右軸）持續往下，市場進入恐慌模式" },
    { icon: "🔵→🩷", label: "柱子從藍色變桃紅色", desc: "Put IV 被拉高，權利金變厚，開始評估 CSP 進場時機" },
    { icon: "⏳", label: "桃紅色持續 2～3 根", desc: "恐慌情緒累積期，繼續觀望，不要急著進場" },
    { icon: "📏", label: "桃紅柱明顯縮短那根", desc: "確認進場，開 CSP" },
  ].freeze

  WHEEL_ROWS = [
    { signal: "Skew 藍→桃紅",                    meaning: "SQQQ 短期急速暴漲，市場恐慌爆發",  action: "不要新開 CSP，等待頂部確認",                       highlight: false, color: "text-red-400" },
    { signal: "Skew 持續桃紅 2～3 根",            meaning: "SQQQ 高位震盪，IV 整體拉高",       action: "繼續觀望，等收斂訊號",                              highlight: false, color: "text-orange-400" },
    { signal: "桃紅後首根明顯縮短",               meaning: "SQQQ 頂部臨近，股價即將回落",      action: "✅ 最佳進場點，開高 Strike OTM CSP，權利金最厚",    highlight: true,  color: "text-green-400" },
    { signal: "Skew 回落至藍色、股價開始下跌",    meaning: "SQQQ 從高位回落，IV 仍高",         action: "✅ 可開 CSP，Strike 設在高於現價，緩衝空間大",       highlight: false, color: "text-blue-400" },
    { signal: "Skew 藍柱穩定、股價已在低位",      meaning: "IV 下降，整體平靜",                action: "⚠️ 權利金變薄，評估是否划算再進場",                  highlight: false, color: "text-yellow-400" },
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
        h2(class: "text-2xl font-semibold text-gray-200") { "Skew 底部訊號閱讀順序" }
        span(class: "text-2xl text-gray-500 ml-2") { "（依序觀察 4 個步驟）" }
      end

      div(class: "space-y-3") do
        SIGNAL_STEPS.each_with_index do |step, i|
          div(class: "flex gap-4 items-start") do
            div(class: "flex flex-col items-center flex-shrink-0") do
              div(class: "w-7 h-7 rounded-full bg-gray-800 border border-gray-600 flex items-center justify-center text-2xl font-bold text-gray-300") { (i + 1).to_s }
              div(class: "w-px h-4 bg-gray-700 mt-1") unless i == SIGNAL_STEPS.size - 1
            end
            div(class: "pb-2") do
              div(class: "flex items-center gap-2 mb-0.5") do
                span(class: "text-base") { step[:icon] }
                span(class: "#{ i == 3 ? 'text-green-300 font-semibold' : 'text-gray-200' } text-2xl") { step[:label] }
              end
              p(class: "text-2xl text-gray-500 leading-relaxed") { step[:desc] }
            end
          end
        end
      end
      div(class: "mt-5 px-4 py-3 rounded-lg bg-gray-800 border border-gray-700 text-2xl text-gray-400 leading-relaxed space-y-1.5") do
        p(class: "text-gray-200 font-semibold") { "桃紅柱 = Skew 值超過歷史第 75 百分位" }
        p { plain("不是 Put IV 絕對值超過 Call IV，而是：") }
        p(class: "text-gray-300 font-medium pl-2 border-l-2 border-pink-500") { "Put IV 相對 Call IV 的差距，縮小到歷史上前 25% 最窄的程度" }
        p { plain("意思是 Put IV 被拉高、兩者差距異常縮小，超過歷史 75th percentile 閾值就標為桃紅。") }
      end
    end
  end

  def render_wheel_table
    div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
      div(class: "flex items-center gap-2 px-6 py-4 border-b border-gray-700") do
        span(class: "text-lg") { "🎡" }
        h2(class: "text-2xl font-semibold text-gray-200") { "SQQQ Wheel 策略對照表" }
        span(class: "text-2xl text-gray-500 ml-2") { "Put/Call Skew 訊號 → 操作含意" }
      end

      div(class: "overflow-x-auto") do
        table(class: "w-full text-2xl") do
          thead do
            tr(class: "bg-gray-800/60") do
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "觀察到的現象" }
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "市場含意" }
              th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "操作含意" }
            end
          end
          tbody do
            WHEEL_ROWS.each do |row|
              tr(class: "border-t border-gray-800 #{ row[:highlight] ? 'bg-green-950/30' : '' }") do
                td(class: "px-5 py-3 text-gray-300 font-mono leading-relaxed") { row[:signal] }
                td(class: "px-5 py-3 text-gray-400 leading-relaxed") { row[:meaning] }
                td(class: "px-5 py-3 #{row[:color]} font-medium leading-relaxed") { row[:action] }
              end
            end
          end
        end
      end

      div(class: "px-6 py-3 bg-gray-800/40 border-t border-gray-700") do
        p(class: "text-2xl text-gray-500") do
          plain("💡 CSP 甜蜜點 = SQQQ 股價在低位 + IV 仍高 + 賣高於現價的 OTM Strike → 權利金厚、擔保金略多、緩衝大")
        end
      end
    end
  end
end
