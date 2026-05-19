# frozen_string_literal: true

# ── IV Skew 完整說明（可收合）────────────────────────────────
class IvWatchlists::IndexView::IvSkewExplainer < ApplicationComponent
  SKEW_STATES = [
    { dot: "bg-blue-400",  badge: "bg-blue-50 text-blue-700 border-blue-200",  label: "低位（接近 0）",       desc: "市場平靜，無明顯恐慌情緒，正常操作" },
    { dot: "bg-gray-400",  badge: "bg-gray-100 text-gray-700 border-gray-200", label: "中等（正常值）",        desc: "正常的下跌保護溢價，屬市場常態" },
    { dot: "bg-pink-500",  badge: "bg-pink-50 text-pink-700 border-pink-200",  label: "高（> 75th pct）",     desc: "恐慌情緒主導，大量資金搶買 Put 護盤" },
    { dot: "bg-green-500", badge: "bg-green-50 text-green-700 border-green-200", label: "從高位急速回落",       desc: "恐慌釋放完畢，底部訊號，反彈前兆" },
  ].freeze

  PRICE_ROWS = [
    { icon: "📉", border: "border-l-4 border-red-400 bg-red-50",     label_cls: "text-red-700",    label: "Skew 急速飆升超過 75th pct",      desc: "市場恐慌，股價可能正在或即將下跌；不要抄底，等待訊號。" },
    { icon: "⏳", border: "border-l-4 border-orange-400 bg-orange-50", label_cls: "text-orange-700", label: "Skew 維持高位桃紅 2–3 根",         desc: "恐慌情緒累積期，空頭力道仍在，觀望不動作。" },
    { icon: "📏", border: "border-l-4 border-green-500 bg-green-50",  label_cls: "text-green-700",  label: "桃紅柱後首根明顯縮短（關鍵訊號）", desc: "恐慌頂部！空頭動能衰竭，Put 需求快速消退，反彈前最重要的入場前訊號。" },
    { icon: "📈", border: "border-l-4 border-blue-400 bg-blue-50",    label_cls: "text-blue-700",   label: "Skew 回落至藍色、持續收窄",         desc: "市場情緒正常化，多方確認接手，股價回升趨勢確立。" },
  ].freeze

  SIGNAL_TABLE = [
    {
      phenomenon: "Skew 藍→桃紅",
      market:     "SQQQ 短期急速暴漲，市場恐慌爆發",
      action:     "不要新開 CSP，等待頂部確認",
      status:     :wait,
    },
    {
      phenomenon: "Skew 持續桃紅 2～3 根",
      market:     "SQQQ 高位震盪，IV 整體拉高",
      action:     "繼續觀望，等收斂訊號",
      status:     :wait,
    },
    {
      phenomenon: "桃紅後首根明顯縮短",
      market:     "SQQQ 頂部臨近，股價即將回落",
      action:     "✅ 最佳進場點，開高 Strike OTM CSP，權利金最厚",
      status:     :best,
    },
    {
      phenomenon: "Skew 回落至藍色、股價開始下跌",
      market:     "SQQQ 從高位回落，IV 仍高",
      action:     "✅ 可開 CSP，Strike 設在高於現價，緩衝空間大",
      status:     :ok,
    },
    {
      phenomenon: "Skew 藍柱穩定、股價已在低位",
      market:     "IV 下降，整體平靜",
      action:     "⚠️ 權利金變薄，評估是否划算再進場",
      status:     :caution,
    },
  ].freeze

  STATUS_STYLES = {
    wait:    { row: "bg-red-50",    action: "text-red-700 font-medium" },
    best:    { row: "bg-green-50",  action: "text-green-700 font-semibold" },
    ok:      { row: "bg-blue-50",   action: "text-blue-700 font-medium" },
    caution: { row: "bg-yellow-50", action: "text-yellow-700 font-medium" },
  }.freeze

  def view_template
    details(class: "mb-6 rounded-xl border border-gray-200 bg-white overflow-hidden group/exp shadow-sm") do
      summary(class: "flex items-center justify-between px-5 py-3.5 cursor-pointer hover:bg-gray-50 transition-colors list-none select-none border-b border-gray-200") do
        div(class: "flex items-center gap-2.5") do
          span(class: "text-base") { "📖" }
          span(class: "text-2xl font-semibold text-gray-800") { "IV Skew 完整說明" }
          span(class: "text-2xl text-gray-400 font-normal ml-1") { "— 是什麼、如何解讀、CSP 開倉時機" }
        end
        span(class: "text-gray-400 text-2xl transition-transform duration-200 group-open/exp:rotate-180", style: "display:inline-block") { "▼" }
      end
      div(class: "px-5 py-5 space-y-6 bg-white") do
        render_what_is_skew
        render_how_it_works
        render_price_reading
        render_csp_timing
      end
    end
  end

  private

  def render_what_is_skew
    div do
      div(class: "flex items-center gap-2 mb-3") do
        div(class: "w-1 h-4 rounded bg-blue-500") {}
        h3(class: "text-2xl font-semibold text-gray-900") { "IV Skew 是什麼？" }
      end
      div(class: "space-y-2 text-2xl text-gray-700 leading-relaxed") do
        p { plain("IV Skew（隱含波動率偏度）衡量相同到期日下，不同行使價期權之間 IV 差異。本工具使用：") }
        div(class: "my-2 ml-3 px-4 py-2.5 bg-gray-100 rounded-lg border border-gray-200 font-mono text-gray-800 text-2xl") do
          plain("Skew = 25-delta Put IV  −  25-delta Call IV")
        end
        div(class: "my-2 ml-3 px-4 py-3 bg-blue-50 rounded-lg border border-blue-200") do
          p(class: "text-2xl font-semibold text-blue-800 mb-1.5") { "為什麼選 25-delta？" }
          p(class: "text-2xl text-blue-900 mb-1.5") do
            plain("25-delta Put = 買一個保護，行使價大約在現價以下 5–8% 的 Put。這個距離剛好在：")
          end
          div(class: "space-y-1 mb-1.5") do
            div(class: "flex items-start gap-2 text-2xl text-blue-800") do
              span(class: "text-blue-500 flex-shrink-0") { "✗" }
              plain("不是平值（ATM）— 太貴、對價格變動太敏感")
            end
            div(class: "flex items-start gap-2 text-2xl text-blue-800") do
              span(class: "text-blue-500 flex-shrink-0") { "✗" }
              plain("不是深度虛值（far OTM）— 太便宜、保護效果差")
            end
          end
          p(class: "text-2xl text-blue-700 font-medium") { "→ 業界以 25-delta（或 30-delta）作為衡量市場恐慌程度的標準觀察位置。" }
        end
        p { plain("Skew > 0 表示市場對下跌保護的需求大於上漲押注，屬於常態。Skew 數值越高，代表市場越恐慌、願意花越多成本買 Put 保護。") }
      end
    end
  end

  def render_how_it_works
    div do
      div(class: "flex items-center gap-2 mb-3") do
        div(class: "w-1 h-4 rounded bg-purple-500") {}
        h3(class: "text-2xl font-semibold text-gray-900") { "市場情緒計：Skew 的四種狀態" }
      end
      div(class: "space-y-2") do
        SKEW_STATES.each do |s|
          div(class: "flex items-center gap-3 px-3 py-2.5 rounded-lg border #{s[:badge]}") do
            div(class: "w-2.5 h-2.5 rounded-full flex-shrink-0 #{s[:dot]}") {}
            span(class: "text-2xl font-semibold") { s[:label] }
            span(class: "text-2xl opacity-75 ml-1") { "— #{s[:desc]}" }
          end
        end
      end
    end
  end

  def render_price_reading
    div do
      div(class: "flex items-center gap-2 mb-3") do
        div(class: "w-1 h-4 rounded bg-yellow-500") {}
        h3(class: "text-2xl font-semibold text-gray-900") { "如何用 Skew 預判股價方向" }
      end
      div(class: "space-y-2") do
        PRICE_ROWS.each do |row|
          div(class: "flex items-start gap-3 px-3 py-2.5 rounded-lg #{row[:border]}") do
            span(class: "text-base flex-shrink-0") { row[:icon] }
            div do
              span(class: "text-2xl font-semibold #{row[:label_cls]}") { row[:label] }
              p(class: "text-2xl text-gray-600 mt-0.5 leading-relaxed") { row[:desc] }
            end
          end
        end
      end
    end
  end

  def render_csp_timing
    div do
      div(class: "flex items-center gap-2 mb-3") do
        div(class: "w-1 h-4 rounded bg-green-500") {}
        h3(class: "text-2xl font-semibold text-gray-900") { "Put/Call Skew 訊號 → 操作含意" }
      end
      div(class: "rounded-lg border border-gray-200 overflow-hidden") do
        table(class: "w-full text-2xl") do
          thead do
            tr(class: "bg-gray-100 text-gray-700") do
              th(class: "px-3 py-2 text-left font-semibold text-2xl") { "觀察到的現象" }
              th(class: "px-3 py-2 text-left font-semibold text-2xl") { "市場含意" }
              th(class: "px-3 py-2 text-left font-semibold text-2xl") { "操作含意" }
            end
          end
          tbody do
            SIGNAL_TABLE.each do |row|
              styles = STATUS_STYLES[row[:status]]
              tr(class: "border-t border-gray-200 #{styles[:row]}") do
                td(class: "px-3 py-2 text-2xl text-gray-800 font-medium align-top") { row[:phenomenon] }
                td(class: "px-3 py-2 text-2xl text-gray-600 align-top") { row[:market] }
                td(class: "px-3 py-2 text-2xl #{styles[:action]} align-top") { row[:action] }
              end
            end
          end
        end
      end
      div(class: "mt-3 px-3 py-2.5 rounded-lg bg-amber-50 border border-amber-200") do
        p(class: "text-2xl text-amber-800 leading-relaxed") do
          plain("💡 CSP 甜蜜點 = SQQQ 股價在低位 + IV 仍高 + 賣高於現價的 OTM Strike → 權利金厚、擔保金略多、緩衝大")
        end
      end
    end
  end
end
