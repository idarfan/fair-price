# frozen_string_literal: true

class IvAnalysis::EducationComponent < ApplicationComponent
  FORMULA_STYLE = "background:#0d1117; border: 1.5px dashed #a3e635;"
  CHART_BG      = "background:#161b22; border:1px solid #30363d;"

  def view_template
    section(class: "mt-10 space-y-6") do
      section_header
      formula_section
      chart_section
      vega_vanna_section
      key_takeaways
    end
    render_chart_script
  end

  private

  def section_header
    div(class: "border-b border-gray-200 pb-4") do
      h2(class: "text-lg font-bold text-gray-900") { plain "隱含波動率（IV）完整說明" }
      p(class: "mt-1 text-sm text-gray-500") do
        plain "交易觀念為主，以 Black–Scholes 近似公式說明 IV 對期權價格與 Delta 的統治性影響。"
      end
    end
  end

  def formula_section
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
      h3(class: "text-base font-semibold text-gray-800 mb-3") { plain "📐 買權定價公式（ATM 價平 近似）" }
      p(class: "text-sm text-gray-600 leading-relaxed mb-5") do
        plain "以下基於 Black–Scholes 模型，在"
        span(class: "font-semibold text-gray-800") { plain "價平（ATM）附近" }
        plain "適用的買權近似定價公式。本文不推導數學，但這個式子的「關係」是正確的："
      end

      # Dark formula card
      div(class: "rounded-xl p-6 mb-6 text-center", style: FORMULA_STYLE) do
        # Plain-language prefix line
        p(class: "mb-3", style: "font-size:13px; color:#7d8590; letter-spacing:0.03em;") do
          span(style: "color:#e8f5a3; font-weight:600") { plain "C（買權價格）" }
          plain " 約等於"
        end

        # Formula line — 22px
        p(style: "font-size:22px; letter-spacing:0.04em; color:#d4e157; font-style:italic; line-height:1.4;") do
          span(style: "color:#e8f5a3; font-weight:700") { plain "C" }
          span(style: "color:#7ecaf5; font-weight:300; margin:0 8px") { plain "≈" }
          span(style: "color:#81c784; font-weight:700") { plain "Δ" }
          span(style: "color:#b0bec5") { plain "(" }
          span(style: "color:#e8f5a3; font-weight:700") { plain "S" }
          span(style: "color:#b0bec5; margin:0 5px") { plain "−" }
          span(style: "color:#e8f5a3; font-weight:700") { plain "K" }
          span(style: "color:#b0bec5") { plain ")" }
          span(style: "color:#7ecaf5; margin:0 10px") { plain "+" }
          span(style: "color:#b0bec5; font-weight:400; font-style:normal") { plain "0.4" }
          span(style: "color:#7ecaf5; margin:0 5px") { plain "·" }
          span(style: "color:#e8f5a3; font-weight:700") { plain "S" }
          span(style: "color:#7ecaf5; margin:0 5px") { plain "·" }
          span(style: "color:#ffb74d; font-weight:700") { plain "σ" }
          span(style: "color:#7ecaf5; margin:0 5px") { plain "·" }
          span(style: "color:#b0bec5; font-weight:400; font-style:normal") { plain "√" }
          span(style: "color:#e8f5a3; font-weight:700") { plain "T" }
        end

        # Two-term breakdown cards inside formula card
        div(class: "mt-5 flex flex-wrap justify-center gap-4 text-left") do
          div(class: "rounded-lg px-4 py-3 flex-1",
              style: "background:#112240; border:1px solid #1e3a5f; min-width:200px; max-width:260px") do
            p(style: "color:#58a6ff; font-size:0.68rem; font-weight:700; letter-spacing:0.06em; text-transform:uppercase; margin-bottom:4px") do
              plain "① 內涵價值"
            end
            p(style: "color:#c9d1d9; font-size:0.9rem; font-style:italic; margin-bottom:6px") { plain "Δ · (S − K)" }
            p(style: "color:#8b949e; font-size:0.72rem; line-height:1.6") do
              plain "S（股價）− K（行權價）= 「立刻行權能拿到多少錢」。若 S < K（OTM 價外），視同零。乘以 Δ 是因為期權並非直接持股，Delta 代表對股價變動的實際放大比例。"
            end
          end
          div(class: "rounded-lg px-4 py-3 flex-1",
              style: "background:#1a1200; border:1px solid #3d2e00; min-width:200px; max-width:260px") do
            p(style: "color:#d29922; font-size:0.68rem; font-weight:700; letter-spacing:0.06em; text-transform:uppercase; margin-bottom:4px") do
              plain "② 時間價值"
            end
            p(style: "color:#c9d1d9; font-size:0.9rem; font-style:italic; margin-bottom:6px") { plain "0.4 · S · σ · √T" }
            p(style: "color:#8b949e; font-size:0.72rem; line-height:1.6") do
              plain "S · σ · √T 是「股票在剩餘期間的預期波動幅度（1個標準差）」，例如 S=100、σ=30%、T=1年 → 預期震幅 ±$30。0.4 是 ATM 近似係數（B-S 推導：N′(0) = 1/√2π ≈ 0.3989 ≈ 0.4），把預期震幅轉換為期權溢價。"
            end
          end
        end
      end

      # Symbol cards grid
      h4(class: "text-sm font-semibold text-gray-700 mb-3") { plain "符號完整說明" }
      div(class: "grid sm:grid-cols-2 xl:grid-cols-3 gap-3 mb-6") do
        symbol_card("C", "#e8f5a3", "買權價格", "Call Premium", "每股，美元",
          "你為「以 K 買入股票的權利」支付的市場價格。由兩部分疊加：內涵價值（已在價內的真實獲利）＋時間價值（市場對未來波動的定價）。1 份合約通常對應 100 股。")

        symbol_card("Δ", "#81c784", "Delta", "Delta", "0 ~ 1（Call）",
          "股價每漲 $1，期權理論上的價格變化。ATM（價平）≈ 0.5；深度 ITM（價內）→ 趨近 1.0，近似直接持股；深度 OTM（價外）→ 趨近 0.0，幾乎不隨股票移動。亦可近似解讀為「到期時處於價內」的機率。")

        symbol_card("S", "#e8f5a3", "股價", "Stock Price", "美元 / 每股",
          "標的資產的當前市場價格。S 越高，Call 的內涵價值（S − K）越大；Delta 正是衡量期權對 S 每變動 $1 的瞬間敏感度。")

        symbol_card("K", "#e8f5a3", "行權價", "Strike Price", "美元 / 每股",
          "你有權以此價格買入股票的約定價格。S > K → ITM（價內），存在內涵價值；S = K → ATM（價平），Δ ≈ 0.5；S < K → OTM（價外），內涵價值為零，期權總價純為時間價值。")

        symbol_card("σ", "#ffb74d", "隱含波動率", "Implied Volatility", "年化 %（代入如 0.30）",
          "從市場期權成交價「反推」出市場對未來波動的預期，並非歷史波動率。σ 越高，時間價值越貴，期權總價越高。本工具計算的 IVR / IVP 正是衡量當前 σ 在歷史分布中的相對高低。")

        symbol_card("T", "#e8f5a3", "到期時間", "Time to Expiration", "年（1 月 ≈ 0.083）",
          "公式採 √T 源自隨機漫步理論：資產價格分布的標準差與時間的平方根成正比，而非線性。T 趨近 0 時時間價值加速歸零——即每日 Theta 耗損在到期週前急劇放大的原因。")

        symbol_card("0.4", "#b0bec5", "ATM 近似係數", "≈ 1/√(2π) ≈ 0.3989", "僅 ATM 附近有效",
          "源自 B-S 推導：時間價值項係數為 N′(d₁)，N′ 是標準常態分配的機率密度函數（PDF）。當期權恰好 ATM 時 d₁ ≈ 0，N′(0) = 1/√(2π) ≈ 0.3989 ≈ 0.4。深度 OTM（價外）或 ITM（價內）時此近似誤差較大，需用完整 B-S 公式。")
      end

      div(class: "grid sm:grid-cols-2 gap-4") do
        value_box("內涵價值（Intrinsic Value）", "Δ · (S − K)",
          "期權「已在價內」的真實獲利部分。若 S < K（OTM 價外），此項趨近於零，期權總價幾乎全是時間價值。",
          "border-blue-200 bg-blue-50", "text-blue-700")
        value_box("時間價值（Time Value）", "0.4 · S · σ · √T",
          "S·σ·√T 是股票的預期震幅（1個標準差）；0.4 把它轉換成期權溢價。IV（σ）越高震幅越大，時間價值越貴；T 越小震幅越小，溢價越快消失（Theta 耗損）。",
          "border-orange-200 bg-orange-50", "text-orange-700")
      end
      p(class: "mt-4 text-sm text-gray-600 leading-relaxed") do
        plain "乍看之下，σ 只是時間價值裡的一個乘數。但這只是表面——因為 "
        span(class: "font-semibold text-gray-800") { plain "Δ 本身也和 σ 高度相關" }
        plain "，接下來的圖表正是要展示這個關鍵事實。"
      end
    end
  end

  def symbol_card(sym, color, name_zh, name_en, unit, desc)
    div(class: "rounded-lg border border-gray-200 bg-gray-50 p-3.5") do
      div(class: "flex items-start gap-2.5 mb-2") do
        span(style: "font-size:1.4rem; font-weight:700; font-style:italic; color:#{color}; line-height:1.1; flex-shrink:0") { plain sym }
        div(class: "flex-1 min-w-0") do
          p(class: "text-xs font-bold text-gray-800 leading-tight") { plain name_zh }
          p(class: "text-xs text-gray-400 leading-tight mt-0.5") { plain name_en }
        end
        span(class: "text-xs rounded-full px-2 py-0.5 bg-white border border-gray-200 text-gray-500 whitespace-nowrap flex-shrink-0",
             style: "font-size:0.65rem") { plain unit }
      end
      p(class: "text-xs text-gray-600 leading-relaxed") { plain desc }
    end
  end

  def value_box(title, formula, desc, border_class, color_class)
    div(class: "rounded-lg border p-4 #{border_class}") do
      p(class: "text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1") { plain title }
      p(class: "font-mono font-bold text-base #{color_class} mb-2") { plain formula }
      p(class: "text-xs text-gray-600 leading-relaxed") { plain desc }
    end
  end

  def chart_section
    div(class: "rounded-xl overflow-hidden shadow-sm", style: CHART_BG) do
      div(class: "px-5 pt-4 pb-2 flex flex-wrap items-start justify-between gap-3") do
        div do
          h3(class: "font-bold", style: "color:#e6edf3; font-size:1rem") { plain "期權 Delta 與履約價關係" }
          p(class: "text-xs mt-0.5", style: "color:#7d8590") do
            plain "不同 IV 底下，Call Delta 隨履約價的分布（標的價格 = 100，剩餘時間 1 年）"
          end
        end
        div(class: "flex gap-4 text-xs", style: "color:#7d8590") do
          [["標的價格", "100"], ["剩餘時間", "1.00 年"], ["利率 (R)", "0%"]].each do |k, v|
            div(class: "text-center") do
              div(style: "color:#e6edf3; font-weight:600; font-size:0.85rem") { plain v }
              div { plain k }
            end
          end
        end
      end
      div(class: "px-5 pb-2 flex gap-4") do
        [["10%", "#58a6ff"], ["30%", "#3fb950"], ["50%", "#d29922"], ["80%", "#bc8cff"]].each do |label, color|
          div(class: "flex items-center gap-1.5 text-xs", style: "color:#7d8590") do
            div(class: "w-8 rounded-full", style: "height:2px; background:#{color}")
            span { plain label }
          end
        end
      end
      div(class: "px-2 pb-4") do
        canvas(id: "iv-delta-chart", class: "w-full", height: "320",
               style: "max-height:320px; display:block;")
      end
      div(class: "mx-4 mb-4 rounded-lg p-4", style: "background:#1f2937; border:1px solid #374151;") do
        p(class: "font-semibold text-sm mb-2", style: "color:#fbbf24") { plain "📌 從圖表看出的關鍵事實" }
        ul(class: "space-y-1") do
          ["IV = 10% 時，履約價 115 的 OTM（價外）Call Delta 幾乎趨近於 0 ——買了幾乎不動",
           "IV = 80% 時，同樣履約價 115 的 Delta 可達 0.4 以上 ——對股價極度敏感",
           "IV 上升 8 倍（10% → 80%），OTM（價外）Call 的 Δ 可能翻倍甚至高達五倍",
           "無論是內涵價值（Δ 變大）還是時間價值（σ 直接乘進去），都以倍數放大"].each do |txt|
            li(class: "text-xs leading-relaxed", style: "color:#9ca3af") do
              span(style: "color:#6b7280; margin-right:6px") { plain "•" }
              plain txt
            end
          end
        end
      end
    end
  end

  def vega_vanna_section
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
      h3(class: "text-base font-semibold text-gray-800 mb-4") do
        plain "⚡ Vega 與 Vanna：「贏了方向，輸了波動率」"
      end
      div(class: "grid sm:grid-cols-2 gap-4 mb-5") do
        greek_box("Vega （𝒱）", "期權價格對 IV 變化的敏感度",
          "買入期權就是持有正 Vega。IV 每上升 1%，期權價值增加；IV 下降 1%，期權價值減少。",
          "border-purple-200 bg-purple-50", "text-purple-800")
        greek_box("Vanna", "IV 變化 → Delta 變化（同時也是股價變化 → Vega 變化）",
          "IV 崩潰時，Vanna 把你的 OTM（價外）Delta 從 0.4 打回 0.05——此後即便股票漲了，你也賺不到錢。",
          "border-red-200 bg-red-50", "text-red-800")
      end
      div(class: "rounded-lg border border-gray-200 overflow-hidden") do
        div(class: "px-4 py-2.5 bg-gray-50 border-b border-gray-200") do
          p(class: "text-xs font-semibold text-gray-600 uppercase tracking-wide") do
            plain "財報後情境：你買了 OTM（價外）Call，股票確實漲了，但你卻虧損了"
          end
        end
        div(class: "divide-y divide-gray-100") do
          scenario_row("財報前（IV = 80%）",  "OTM（價外）Call Δ = 0.45，期權價格 = $8.50", "text-gray-700", "")
          scenario_row("財報後股票漲 3%",     "IV 從 80% 崩潰至 25%",                       "text-red-700",  "⚠️")
          scenario_row("Vanna 效應",          "Δ 從 0.45 暴跌至 0.12",                      "text-red-700",  "⚠️")
          scenario_row("Vega 損失",           "IV 崩 55%，時間價值大幅蒸發",                 "text-red-700",  "⚠️")
          scenario_row("最終結果",            "期權從 $8.50 → $3.20，虧損 62%",             "text-red-800 font-semibold", "❌")
        end
      end
    end
  end

  def greek_box(title, subtitle, desc, border_class, title_color)
    div(class: "rounded-lg border p-4 #{border_class}") do
      p(class: "font-semibold text-sm #{title_color} mb-0.5") { plain title }
      p(class: "text-xs text-gray-500 mb-2 italic") { plain subtitle }
      p(class: "text-xs text-gray-700 leading-relaxed") { plain desc }
    end
  end

  def scenario_row(label, value, value_class, icon)
    div(class: "flex items-start gap-3 px-4 py-2.5 text-sm") do
      span(class: "text-xs text-gray-400 w-4 flex-shrink-0 mt-0.5") { plain icon }
      span(class: "text-gray-600 w-44 flex-shrink-0") { plain label }
      span(class: value_class) { plain value }
    end
  end

  def key_takeaways
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
      h3(class: "text-base font-semibold text-gray-800 mb-4") { plain "🎯 實戰要點" }
      div(class: "space-y-3") do
        takeaway("低 IV 買期權（IVR < 20%）",
          "IV 低時，時間價值便宜；Vanna 效應讓 OTM（價外）Delta 還有上升空間。若 IV 後續回升，Vega 和 Vanna 雙重受益。這正是 IVR 低點買入期權的核心邏輯。",
          "border-green-200 bg-green-50", "text-green-700")
        takeaway("高 IV 避免買 OTM（價外）期權（IVR > 80%）",
          "高 IV 代表市場已充分定價未來波動。財報等事件過後，IV 一旦崩潰，Vega 損失加上 Vanna 讓 Delta 歸零，方向做對了也可能虧錢。",
          "border-red-200 bg-red-50", "text-red-700")
        takeaway("高 IV 環境的替代策略：深度 ITM（價內）或現股",
          "若 IV 很高但你仍看好方向，可選深度 ITM（價內）短期期權甚至直接買現股。深度 ITM（價內）讓 (S−K) 佔主導，時間價值極小，IV 崩潰的衝擊也就微乎其微。",
          "border-blue-200 bg-blue-50", "text-blue-700")
        takeaway("高 IV 環境的賣方策略",
          "賣出期權（如 Covered Call、Cash-Secured Put、Vertical Spread）可收取高額 IV 溢價。當 IV 回落，正 Theta 和負 Vega 雙重獲益。需注意賣方面臨 Gamma 風險。",
          "border-purple-200 bg-purple-50", "text-purple-700")
        hv_iv_box
        ivr_wheel_table
      end
      p(class: "mt-5 text-xs text-gray-400 italic") do
        plain "本文僅為教育說明，不構成投資建議。期權交易涉及複雜風險，請自行評估。"
      end
    end
  end

  def takeaway(title, desc, border_class, title_color)
    div(class: "rounded-lg border p-4 #{border_class}") do
      p(class: "font-semibold text-sm #{title_color} mb-1") { plain title }
      p(class: "text-sm text-gray-700 leading-relaxed") { plain desc }
    end
  end

  def hv_iv_box
    div(class: "rounded-lg border border-gray-200 p-4 bg-gray-50") do
      p(class: "font-semibold text-sm text-gray-800 mb-3") { plain "📊 HV（歷史波動率）vs IV（隱含波動率）" }

      div(class: "grid sm:grid-cols-2 gap-3 mb-4") do
        div(class: "rounded-lg border border-gray-200 bg-white p-3") do
          p(class: "text-xs font-bold text-gray-700 mb-1") { plain "HV — Historic Volatility" }
          p(class: "text-xs text-gray-600 leading-relaxed") do
            plain "過去實際發生的波動率，用過去 30 天的每日漲跌幅計算年化標準差。代表「股票過去真實波動了多劇烈」。"
          end
        end
        div(class: "rounded-lg border border-gray-200 bg-white p-3") do
          p(class: "text-xs font-bold text-gray-700 mb-1") { plain "IV — Implied Volatility" }
          p(class: "text-xs text-gray-600 leading-relaxed") do
            plain "市場對未來波動率的預期，從期權價格反推回來。代表「市場認為接下來會波動多劇烈」。"
          end
        end
      end

      div(class: "space-y-2") do
        div(class: "flex items-start gap-3 rounded-lg border border-green-200 bg-green-50 px-3 py-2.5") do
          span(class: "text-xs font-bold text-green-700 whitespace-nowrap mt-0.5") { plain "HV > IV" }
          p(class: "text-xs text-gray-700 leading-relaxed") do
            plain "過去波動比市場預期大，期權相對便宜（以歷史標準衡量）。"
            span(class: "font-semibold text-green-700") { plain "買方略為有利" }
            plain "，CSP 等賣方策略權利金偏薄。"
          end
        end
        div(class: "flex items-start gap-3 rounded-lg border border-orange-200 bg-orange-50 px-3 py-2.5") do
          span(class: "text-xs font-bold text-orange-700 whitespace-nowrap mt-0.5") { plain "IV > HV" }
          p(class: "text-xs text-gray-700 leading-relaxed") do
            plain "期權被高估（相對於實際波動）。"
            span(class: "font-semibold text-orange-700") { plain "賣方策略（Wheel）更有利" }
            plain "，可收取超額 IV 溢價。"
          end
        end
      end
    end
  end

  def ivr_wheel_table
    rows = [
      ["0 ~ 20%",   "IV 處於一年低點",  "適合買期權，CSP 權利金偏薄",   "bg-green-100 text-green-800",  "text-green-700"],
      ["20 ~ 40%",  "偏低",             "CSP 尚可，收益普通",            "bg-green-50 text-green-700",   "text-green-600"],
      ["40 ~ 60%",  "中性",             "Wheel 正常運作",                "bg-gray-50 text-gray-700",     "text-gray-600"],
      ["60 ~ 80%",  "偏高",             "Wheel 收益豐厚",                "bg-orange-50 text-orange-700", "text-orange-600"],
      ["80 ~ 100%", "IV 處於一年高點",  "賣方天堂，但注意方向風險",       "bg-red-100 text-red-800",      "text-red-700"],
    ]

    div(class: "rounded-lg border border-gray-200 overflow-hidden") do
      div(class: "px-4 py-2.5 bg-gray-50 border-b border-gray-200") do
        p(class: "text-xs font-semibold text-gray-700") { plain "📈 IV Rank（IVR）對 Wheel 策略的意義" }
        p(class: "text-xs text-gray-500 mt-0.5") do
          plain "IVR = （當前 IV − 一年最低 IV）÷（一年最高 IV − 一年最低 IV）× 100"
        end
      end
      table(class: "w-full text-xs") do
        thead do
          tr(class: "border-b border-gray-200 bg-gray-50") do
            th(class: "px-4 py-2 text-left font-semibold text-gray-500") { plain "IVR 範圍" }
            th(class: "px-4 py-2 text-left font-semibold text-gray-500") { plain "意義" }
            th(class: "px-4 py-2 text-left font-semibold text-gray-500") { plain "對你的 Wheel 策略" }
          end
        end
        tbody do
          rows.each do |range, meaning, strategy, badge_class, strategy_class|
            tr(class: "border-b border-gray-100 last:border-0") do
              td(class: "px-4 py-2.5") do
                span(class: "inline-block px-2 py-0.5 rounded-full text-xs font-bold #{badge_class}") { plain range }
              end
              td(class: "px-4 py-2.5 text-gray-600") { plain meaning }
              td(class: "px-4 py-2.5 font-medium #{strategy_class}") { plain strategy }
            end
          end
        end
      end
    end
  end

  def render_chart_script
    script do
      raw <<~JS.html_safe
        (function () {
          var canvas = document.getElementById('iv-delta-chart');
          if (!canvas) return;
          var ctx = canvas.getContext('2d');

          var dpr  = window.devicePixelRatio || 1;
          var cssW = canvas.clientWidth || 640;
          var cssH = 320;
          canvas.width  = cssW * dpr;
          canvas.height = cssH * dpr;
          ctx.scale(dpr, dpr);

          var W = cssW, H = cssH;
          var pad = { top: 18, right: 24, bottom: 44, left: 52 };
          var cW  = W - pad.left - pad.right;
          var cH  = H - pad.top  - pad.bottom;

          function normCDF(x) {
            var t = 1 / (1 + 0.2316419 * Math.abs(x));
            var d = 0.3989422820 * Math.exp(-x * x / 2);
            var p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.7814779 + t * (-1.8212560 + t * 1.3302744))));
            return x >= 0 ? 1 - p : p;
          }
          function callDelta(S, K, sig, T) {
            if (sig <= 0 || T <= 0) return K <= S ? 1.0 : 0.0;
            var d1 = (Math.log(S / K) + 0.5 * sig * sig * T) / (sig * Math.sqrt(T));
            return normCDF(d1);
          }

          var S = 100, T = 1.0;
          var Kmin = 60, Kmax = 150, steps = 300;
          var ivs = [
            { s: 0.10, c: '#58a6ff' }, { s: 0.30, c: '#3fb950' },
            { s: 0.50, c: '#d29922' }, { s: 0.80, c: '#bc8cff' }
          ];

          function toX(K)     { return pad.left + (K - Kmin) / (Kmax - Kmin) * cW; }
          function toY(delta) { return pad.top  + (1 - delta) * cH; }

          ctx.fillStyle = '#161b22';
          ctx.fillRect(0, 0, W, H);

          ctx.strokeStyle = '#21262d'; ctx.lineWidth = 1;
          [0, 0.25, 0.5, 0.75, 1.0].forEach(function(y) {
            var cy = toY(y);
            ctx.beginPath(); ctx.moveTo(pad.left, cy); ctx.lineTo(pad.left + cW, cy); ctx.stroke();
          });
          [70,80,90,100,110,120,130,140].forEach(function(k) {
            var cx = toX(k);
            ctx.beginPath(); ctx.moveTo(cx, pad.top); ctx.lineTo(cx, pad.top + cH); ctx.stroke();
          });

          // ATM（價平）dashed line
          ctx.strokeStyle = '#444c56'; ctx.setLineDash([5,4]); ctx.lineWidth = 1.5;
          var ax = toX(100);
          ctx.beginPath(); ctx.moveTo(ax, pad.top); ctx.lineTo(ax, pad.top + cH); ctx.stroke();
          ctx.setLineDash([]);

          ctx.fillStyle = '#7d8590'; ctx.font = '11px sans-serif';
          ctx.textAlign = 'left';
          ctx.fillText('價平 ATM: 100', ax + 5, pad.top + 14);
          ctx.textAlign = 'right';
          [0, 0.25, 0.5, 0.75, 1.0].forEach(function(y) {
            ctx.fillText(y.toFixed(2), pad.left - 6, toY(y) + 4);
          });
          ctx.textAlign = 'center';
          [70,80,90,100,110,120,130,140].forEach(function(k) {
            ctx.fillText(k, toX(k), pad.top + cH + 16);
          });
          ctx.fillStyle = '#9ca3af'; ctx.font = 'bold 11px sans-serif';
          ctx.fillText('履約價 Strike', pad.left + cW / 2, H - 6);
          ctx.save(); ctx.translate(13, pad.top + cH / 2); ctx.rotate(-Math.PI/2);
          ctx.fillText('買權 Delta', 0, 0); ctx.restore();

          ivs.forEach(function(iv) {
            ctx.beginPath(); ctx.strokeStyle = iv.c; ctx.lineWidth = 2.5;
            ctx.shadowColor = iv.c; ctx.shadowBlur = 4;
            for (var i = 0; i <= steps; i++) {
              var K = Kmin + (Kmax - Kmin) * i / steps;
              var d = callDelta(S, K, iv.s, T);
              i === 0 ? ctx.moveTo(toX(K), toY(d)) : ctx.lineTo(toX(K), toY(d));
            }
            ctx.stroke(); ctx.shadowBlur = 0;
          });

          ctx.strokeStyle = '#30363d'; ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.moveTo(pad.left, pad.top); ctx.lineTo(pad.left, pad.top + cH);
          ctx.lineTo(pad.left + cW, pad.top + cH); ctx.stroke();
        })();
      JS
    end
  end
end
