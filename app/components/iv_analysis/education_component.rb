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
      chain_glossary_section
    end
    render_chart_script
    render_chain_tooltip_script
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
        real_example_box
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

  def real_example_box
    div(class: "rounded-lg border border-gray-200 overflow-hidden") do
      div(class: "px-4 py-3 bg-gray-50 border-b border-gray-200") do
        p(class: "text-xs font-semibold text-gray-700") { plain "🖼 真實案例：Barchart 選擇權鏈（SQQQ, 2026-05-15 到期）" }
        p(class: "text-xs text-gray-500 mt-0.5") do
          plain "以下截圖中，最上方資訊欄的四個數字，正是本工具計算的核心指標。"
        end
      end

      # Screenshot with interactive column tooltips
      div(class: "p-4") do
        p(class: "text-xs text-gray-400 mb-2") { plain "— 滑鼠移到任一欄位可查看說明" }
        div(id: "barchart-img-container",
            class: "relative rounded-lg border border-gray-200 shadow-sm overflow-hidden") do
          img(
            src:   "/images/options_chain_example.png",
            alt:   "Barchart 選擇權鏈截圖",
            class: "w-full block select-none",
            style: "display:block"
          )
          div(id: "barchart-col-hl", class: "absolute inset-y-0 pointer-events-none",
              style: "opacity:0;background:rgba(59,130,246,0.18);transition:left 0.06s,width 0.06s;")
        end
      end

      # Barchart tooltip overlay (fixed, JS-managed)
      div(id: "barchart-col-tooltip",
          class: "hidden fixed z-50 rounded-xl shadow-2xl overflow-hidden select-none",
          style: "max-width:320px;pointer-events:none;border:1px solid #e5e7eb;") do
        div(id: "barchart-tt-hdr", class: "px-4 py-3 flex items-center gap-2") do
          span(id: "barchart-tt-num",
               class: "w-6 h-6 rounded-full flex items-center justify-center text-white flex-shrink-0 font-bold",
               style: "font-size:0.82rem;background:rgba(0,0,0,0.25)")
          div(class: "flex-1 min-w-0") do
            p(id: "barchart-tt-en", class: "font-bold font-mono text-white leading-tight", style: "font-size:0.95rem")
            p(id: "barchart-tt-zh", class: "mt-0.5", style: "font-size:0.82rem;color:rgba(255,255,255,0.85)")
          end
          span(id: "barchart-tt-ex",
               class: "ml-auto font-mono rounded px-2 py-0.5 whitespace-nowrap flex-shrink-0",
               style: "font-size:0.82rem;background:rgba(0,0,0,0.2);color:rgba(255,255,255,0.9)")
        end
        div(class: "bg-white px-4 py-3") do
          p(id: "barchart-tt-sum",
            class: "text-gray-800 font-medium leading-relaxed mb-2",
            style: "font-size:0.85rem")
          div(id: "barchart-tt-bul", class: "space-y-1")
        end
      end

      # Annotation grid
      div(class: "grid sm:grid-cols-2 xl:grid-cols-4 gap-3 px-4 pb-4") do
        annotation_card(
          "Expiration", "2026-05-15 (13 DTE)",
          "到期日與剩餘天數（Days to Expiration）。",
          "border-gray-300 bg-gray-50", "text-gray-700"
        )
        annotation_card(
          "Implied Volatility (ATM)", "59.71%",
          "平值（ATM）隱含波動率，從市場期權價格反推的「市場預期未來波動率」。本工具的 ATM IV 欄位即為此值。",
          "border-blue-200 bg-blue-50", "text-blue-700"
        )
        annotation_card(
          "Historic Volatility", "62.72%",
          "過去 30 個交易日收盤價漲跌幅的年化標準差，代表「股票過去真實波動了多劇烈」。本工具的 HV (21d) 欄位與此對應（窗口略有差異）。",
          "border-green-200 bg-green-50", "text-green-700"
        )
        annotation_card(
          "IV Rank", "37.04%",
          "當前 IV 在過去一年高低區間的相對位置。37% 代表偏低但非極低，CSP 收益普通。本工具的 IVR 1Y 欄位即為此值。",
          "border-orange-200 bg-orange-50", "text-orange-700"
        )
      end

      # HV > IV interpretation for this specific example
      div(class: "mx-4 mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3") do
        p(class: "text-xs font-semibold text-amber-800 mb-1") { plain "📌 解讀這組數字（HV 62.72% > IV 59.71%）" }
        div(class: "text-xs text-amber-900 leading-relaxed space-y-1") do
          p { plain "• HV 比 IV 略高，代表過去實際波動比市場預期的還要大，期權以歷史標準衡量算相對便宜。" }
          p { plain "• 不過差距僅 3%，優勢並不顯著，不算強烈的買方訊號。" }
          p { plain "• IV Rank 37%，介於 20~40% 偏低區間，賣出 CSP 收益普通，市場未給出高溢價。" }
          p { plain "• 結論：目前 IV 環境對買賣雙方均無明顯優勢，觀察等待 IVR 回到 60% 以上再賣 Wheel 更為有利。" }
        end
      end
    end
  end

  def annotation_card(title, value, desc, border_class, value_class)
    div(class: "rounded-lg border p-3 #{border_class}") do
      p(class: "text-xs font-bold #{value_class} mb-0.5") { plain value }
      p(class: "text-xs font-semibold text-gray-600 mb-1") { plain title }
      p(class: "text-xs text-gray-600 leading-relaxed") { plain desc }
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


  def chain_glossary_section
    div(class: "mt-8 bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      # Header
      div(class: "px-6 pt-6 pb-4 border-b border-gray-100") do
        h2(class: "text-lg font-bold text-gray-900") { plain "📋 選擇權鏈欄位完整說明" }
        p(class: "mt-1 text-sm text-gray-500") do
          plain "對照下方截圖，每個編號說明一個欄位的意義，讓你查表時不再霧裡看花。"
        end
      end

      # Screenshot with interactive hover tooltips per column
      div(class: "px-6 pt-5 pb-3") do
        p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2") do
          plain "實際範例（Puts 選擇權鏈）"
          span(class: "ml-2 font-normal text-gray-400 normal-case") { plain "— 滑鼠移到任一欄可查看說明" }
        end
        div(id: "chain-img-container",
            class: "relative rounded-lg border border-gray-200 shadow-sm overflow-hidden") do
          img(
            src:   "/images/options_chain_puts_example.png",
            alt:   "選擇權 Puts 報價表截圖",
            class: "w-full block select-none",
            style: "display:block"
          )
          # column highlight overlay — JS manages left/width dynamically
          div(id: "chain-col-hl", class: "absolute inset-y-0 pointer-events-none", style: "opacity:0;background:rgba(59,130,246,0.18);transition:left 0.06s,width 0.06s;")
        end
        p(class: "mt-2 text-xs text-gray-400") do
          plain "① Strike　② Latest　③ Theor.　④ IV　⑤ Delta　⑥ Gamma　⑦ Theta　⑧ Vega　⑨ Rho　⑩ Volume　⑪ Open Int　⑫ Vol/OI　⑬ ITM Prob　⑭ Type"
        end
      end

      # Fixed tooltip overlay — JS fills & positions on hover
      div(id: "chain-col-tooltip",
          class: "hidden fixed z-50 rounded-xl shadow-2xl overflow-hidden select-none",
          style: "max-width:300px;pointer-events:none;border:1px solid #e5e7eb;") do
        div(id: "chain-tt-hdr", class: "px-4 py-3 flex items-center gap-2") do
          span(id: "chain-tt-num",
               class: "w-6 h-6 rounded-full flex items-center justify-center text-white flex-shrink-0 font-bold",
               style: "font-size:0.7rem;background:rgba(0,0,0,0.25)")
          div(class: "flex-1 min-w-0") do
            p(id: "chain-tt-en", class: "text-sm font-bold font-mono text-white leading-tight")
            p(id: "chain-tt-zh", class: "text-xs mt-0.5", style: "color:rgba(255,255,255,0.8)")
          end
          span(id: "chain-tt-ex",
               class: "ml-auto text-xs font-mono rounded px-2 py-0.5 whitespace-nowrap flex-shrink-0",
               style: "background:rgba(0,0,0,0.2);color:rgba(255,255,255,0.9)")
        end
        div(class: "bg-white px-4 py-3") do
          p(id: "chain-tt-sum", class: "text-gray-800 font-medium leading-relaxed mb-2", style: "font-size:0.85rem")
          div(id: "chain-tt-bul", class: "space-y-1")
        end
      end

      # Tipdoc cards grid
      div(class: "px-6 pb-6") do
        div(class: "mb-4 mt-2") do
          h3(class: "text-sm font-semibold text-gray-700") { plain "各欄位說明" }
        end

        # Row 1: 價格 & IV (4 cards)
        div(class: "mb-3") do
          p(class: "text-xs font-bold text-blue-600 uppercase tracking-wide mb-2") { plain "💰 價格與波動率" }
          div(class: "grid sm:grid-cols-2 xl:grid-cols-4 gap-3") do
            tipdoc("①", "Strike", "行權價", "#3b82f6",
              "你有權以此價格買（Call）或賣（Put）股票。",
              "股價 > Strike → Call 在價內（ITM）
股價 < Strike → Put 在價內（ITM）",
              "$80.00")
            tipdoc("②", "Latest", "最新成交價", "#3b82f6",
              "這份期權在市場上最後成交的價格。",
              "1 份合約 = 100 股
實際費用 = Latest × 100 美元",
              "$2.05")
            tipdoc("③", "Theor.", "理論價值", "#8b5cf6",
              "用 Black–Scholes 公式算出的「合理」價格。",
              "Latest ≈ Theor. → 流動性好
差距太大 → Bid/Ask 價差寬，小心",
              "$2.05")
            tipdoc("④", "IV", "隱含波動率", "#f59e0b",
              "把 Latest 代入 B-S 模型「反推」出來的波動率預期。",
              "IV 高 → 期權貴，賣方策略有利
IV 低 → 期權便宜，買方策略有利
IVR / IVP 就是衡量它的歷史位置",
              "57.42%")
          end
        end

        # Row 2: Greeks (5 cards)
        div(class: "mb-3") do
          p(class: "text-xs font-bold text-green-600 uppercase tracking-wide mb-2") { plain "🔢 Greeks（風險敏感度）" }
          div(class: "grid sm:grid-cols-2 xl:grid-cols-3 gap-3") do
            tipdoc("⑤", "Delta", "方向敏感度", "#10b981",
              "股價每漲 $1，期權價格的理論變化（Put Delta 為負值）。",
              "Call: 0 ~ 1（正值）
Put: −1 ~ 0（負值）
ATM ≈ ±0.50，也近似「到期在價內的機率」
─ 計算範例（Delta = −0.4482 的 Put）─
股價跌 $1 → −0.4482 × (−1) = 期權漲 +$0.4482
股價漲 $1 → −0.4482 × (+1) = 期權跌 −$0.4482
⚠ 注意：這是理論值（瞬間線性估計）
實際還要考慮 Gamma（Delta 本身隨股價改變）
Theta（時間侵蝕）及 Bid/Ask 價差
股價大幅波動時誤差會更大",
              "−0.4482")
            tipdoc("⑥", "Gamma", "Delta 的加速度", "#10b981",
              "股價每漲 $1，Delta 本身的變化量。",
              "越接近到期 & ATM → Gamma 越大
買方：方向對了會加速獲利
賣方：要注意方向逆轉的風險",
              "0.0094")
            tipdoc("⑦", "Theta", "每日時間耗損", "#ef4444",
              "每過一天，期權價值的理論消耗（通常為負數）。",
              "時間是買方的敵人、賣方的朋友
越接近到期日 Theta 越大
快到期的 OTM 期權可能一夜變廢紙",
              "−0.0408")
            tipdoc("⑧", "Vega", "波動率敏感度", "#f59e0b",
              "IV 每上升 1%，期權價值的理論變化。",
              "正 Vega（買方）= IV 漲受益
財報後 IV 崩潰 → Vega 陷阱
方向做對了，IV 暴跌仍可能虧損",
              "0.0972")
            tipdoc("⑨", "Rho", "利率敏感度", "#6b7280",
              "無風險利率每上升 1%，期權價值的變化。",
              "日常交易中影響最小，可忽略
只有持有 LEAPS（2 年以上長期期權）時才需注意",
              "−0.0273")
          end
        end

        # Row 3: 流動性 & 機率 (5 cards)
        div do
          p(class: "text-xs font-bold text-sky-600 uppercase tracking-wide mb-2") { plain "📊 成交量、流動性與機率" }
          div(class: "grid sm:grid-cols-2 xl:grid-cols-3 gap-3") do
            tipdoc("⑩", "Volume", "當日成交量", "#0ea5e9",
              "今天共有多少份合約在市場上成交。",
              "Volume 高 → 活絡，容易買賣
Volume 低 → Bid/Ask 價差大，成本高",
              "60")
            tipdoc("⑪", "Open Int", "未平倉量", "#0ea5e9",
              "目前市場上尚未結算的合約總量。",
              "Open Int 大 → 流動性好，有足夠對手盤
增加 → 有新倉位建立
減少 → 有人平倉或到期",
              "792")
            tipdoc("⑫", "Vol/OI", "當日交投比", "#0ea5e9",
              "Volume ÷ Open Interest。",
              "比值高 → 今天動靜大，可能有大戶佈局
是觀察異常活動的快速指標",
              "0.08")
            tipdoc("⑬", "ITM Prob", "到期價內機率", "#8b5cf6",
              "到期時「處於價內」的估計機率，由 Delta 近似。",
              "賣 CSP 常選 ITM Prob < 20% 的 Strike
= 約 80% 的機率讓期權到期歸零
勝率的直觀表達",
              "18.21%")
            tipdoc("⑭", "Type", "Call / Put 類型", "#64748b",
              "標示這是看漲（Call）還是看跌（Put）合約。",
              "Call → 有權以 Strike 買入股票
Put → 有權以 Strike 賣出股票
Wheel: 賣 Put（CSP）或賣 Call（CC）",
              "Put")
          end
        end
      end
    end
  end

  def tipdoc(num, en_name, zh_name, accent, summary, bullets, example)
    div(class: "rounded-lg bg-white",
        style: "border: 1px solid #e5e7eb; border-left: 4px solid #{accent};") do
      div(class: "p-3.5") do
        # Header row
        div(class: "flex items-start justify-between gap-2 mb-2") do
          div(class: "flex items-center gap-1.5") do
            span(class: "inline-flex items-center justify-center w-5 h-5 rounded-full text-white text-xs font-bold flex-shrink-0",
                 style: "background:#{accent}; font-size:0.65rem") { plain num }
            div do
              p(class: "text-sm font-bold font-mono text-gray-900 leading-tight") { plain en_name }
              p(class: "text-xs text-gray-500 mt-0.5") { plain zh_name }
            end
          end
          span(class: "text-xs font-mono rounded px-1.5 py-0.5 bg-gray-100 text-gray-400 whitespace-nowrap flex-shrink-0",
               style: "font-size:0.65rem") { plain example }
        end
        # Summary
        p(class: "text-xs text-gray-700 leading-relaxed mb-1.5") { plain summary }
        # Bullet lines
        div(class: "space-y-0.5") do
          bullets.split("\n").each do |line|
            p(class: "text-xs text-gray-500 leading-relaxed") do
              span(class: "mr-1", style: "color:#{accent}") { plain "›" }
              plain line
            end
          end
        end
      end
    end
  end


  def gloss_group_label(title, subtitle)
    div(class: "mt-5 mb-3") do
      h3(class: "text-sm font-bold text-gray-800") { plain title }
      p(class: "text-xs text-gray-500 mt-0.5") { plain subtitle }
    end
  end

  def gloss_card(en_name, zh_name, accent_color, example, desc)
    div(class: "rounded-lg bg-white overflow-hidden",
        style: "border: 1px solid #e5e7eb; border-left: 4px solid #{accent_color};") do
      div(class: "p-3.5 flex flex-col gap-2") do
        div(class: "flex items-start justify-between gap-2") do
          div do
            p(class: "text-base font-bold font-mono text-gray-900 leading-tight") { plain en_name }
            p(class: "text-xs text-gray-500 mt-0.5") { plain zh_name }
          end
          span(class: "text-xs rounded px-1.5 py-0.5 bg-gray-100 text-gray-400 font-mono whitespace-nowrap flex-shrink-0",
               style: "font-size:0.65rem") { plain example }
        end
        p(class: "text-xs text-gray-600 leading-relaxed") { plain desc }
      end
    end
  end

  def render_chain_tooltip_script
    script do
      raw <<~JS.html_safe
        (function () {
          var wrapper = document.getElementById('chain-img-container');
          var tip     = document.getElementById('chain-col-tooltip');
          var hl      = document.getElementById('chain-col-hl');
          if (!wrapper || !tip || !hl) return;

          var hdr = document.getElementById('chain-tt-hdr');
          var num = document.getElementById('chain-tt-num');
          var en  = document.getElementById('chain-tt-en');
          var zh  = document.getElementById('chain-tt-zh');
          var ex  = document.getElementById('chain-tt-ex');
          var sm  = document.getElementById('chain-tt-sum');
          var bl  = document.getElementById('chain-tt-bul');

          // Column left-boundary percentages (derived from 1077px image pixel analysis)
          var BOUNDS = [0, 8.3, 15.5, 22.5, 29.0, 35.3, 42.5, 49.0, 55.4, 62.2, 69.7, 77.7, 85.5, 93.0, 100];

          var COLS = [
            { num:'①', en:'Strike',   zh:'行權價',      color:'#3b82f6', example:'$80.00',
              summary:'你有權以此價格買（Call）或賣（Put）股票。',
              bullets:['股價 > Strike → Call 在價內（ITM）','股價 < Strike → Put 在價內（ITM）','反之稱為價外（OTM）'] },
            { num:'②', en:'Latest',   zh:'最新成交價',   color:'#3b82f6', example:'$2.05',
              summary:'這份期權在市場上最後成交的價格，即買入需付的費用。',
              bullets:['1 份合約 = 100 股，費用 = Latest x 100 美元','流動性差時 Latest 可能遠離合理價','搭配 Theor. 確認定價是否合理'] },
            { num:'③', en:'Theor.',   zh:'理論價值',     color:'#8b5cf6', example:'$2.05',
              summary:'用 Black-Scholes 公式計算出來的「合理」期權價格。',
              bullets:['Latest = Theor. 流動性好，可放心交易','差距大代表 Bid/Ask 價差寬，進出成本高','常與 Latest 比較，判斷當前定價是否合理'] },
            { num:'④', en:'IV',       zh:'隱含波動率',   color:'#f59e0b', example:'57.42%',
              summary:'把市場成交價代入 B-S 公式反推出的波動率預期。',
              bullets:['IV 高期權貴，賣方策略（Wheel）有利','IV 低期權便宜，買方策略有利','IVR / IVP 正是衡量這個數字在歷史中的位置'] },
            { num:'⑤', en:'Delta',    zh:'方向敏感度',   color:'#10b981', example:'-0.4482',
              summary:'股價每漲 $1，期權價格的理論變化量（Put Delta 為負值）。',
              bullets:[
                'Call: 0~1（正值）；Put: \u22121~0（負值）',
                'ATM \u2248 \u00b10.50，也近似「到期在價內的機率」',
                '\u2500 計算範例（Delta = \u22120.4482 的 Put）\u2500',
                '股價跌 $1 \u2192 \u22120.4482 \u00d7 (\u22121) = 期權漲 +$0.4482',
                '股價漲 $1 \u2192 \u22120.4482 \u00d7 (+1) = 期權跌 \u2212$0.4482',
                '\u26a0 理論值（瞬間線性估計）：實際還要考慮',
                'Gamma（Delta 本身隨股價移動而改變）',
                'Theta（時間流逝侵蝕價值）',
                'Bid/Ask 價差 \u2014 股價大幅波動時誤差更大'
              ] },
            { num:'⑥', en:'Gamma',    zh:'Delta 加速度', color:'#10b981', example:'0.0094',
              summary:'股價每漲 $1，Delta 本身的變化量。',
              bullets:['越接近到期且接近 ATM，Gamma 越大','買方：方向對了，獲利會加速放大','賣方：方向逆轉時 Delta 快速擴大，風險上升'] },
            { num:'⑦', en:'Theta',    zh:'每日時間耗損', color:'#ef4444', example:'-0.0408',
              summary:'每過一天，期權價值的理論消耗（通常為負數）。',
              bullets:['時間是買方的敵人、賣方的朋友','越接近到期 Theta 越大，耗損加速','快到期的 OTM 期權可能一夜之間變成廢紙'] },
            { num:'⑧', en:'Vega',     zh:'波動率敏感度', color:'#f59e0b', example:'0.0972',
              summary:'IV 每上升 1%，期權價值的理論變化。',
              bullets:['買方持有正 Vega：IV 漲受益、IV 跌受損','財報後 IV 崩潰（IV Crush）是正 Vega 的大陷阱','方向做對了，IV 暴跌仍可能讓期權虧損'] },
            { num:'⑨', en:'Rho',      zh:'利率敏感度',   color:'#6b7280', example:'-0.0273',
              summary:'無風險利率每上升 1%，期權價值的變化。',
              bullets:['日常交易中影響最小，通常可忽略','持有 LEAPS 長期期權時才需注意','升息環境：Call 略漲，Put 略跌'] },
            { num:'⑩', en:'Volume',   zh:'當日成交量',   color:'#0ea5e9', example:'60',
              summary:'今天共有多少份合約在市場上成交。',
              bullets:['Volume 高代表活絡，容易以合理價成交','Volume 低時 Bid/Ask 差大，實際成交成本高','搭配 Open Int 一起判斷市場熱度'] },
            { num:'⑪', en:'Open Int', zh:'未平倉量',     color:'#0ea5e9', example:'792',
              summary:'目前市場上尚未結算的合約總量。',
              bullets:['大代表流動性好，有足夠對手盤','增加代表有新倉位建立，資金進場','減少代表有人平倉或合約到期結算'] },
            { num:'⑫', en:'Vol/OI',   zh:'當日交投比',   color:'#0ea5e9', example:'0.08',
              summary:'Volume 除以 Open Interest，衡量今日活躍程度。',
              bullets:['比值突然偏高，可能有大戶或消息面在動','是觀察異常佈局的快速指標','正常情況下多在 0.05~0.2 之間'] },
            { num:'⑬', en:'ITM Prob', zh:'到期價內機率', color:'#8b5cf6', example:'18.21%',
              summary:'到期時「處於價內」的估計機率，由 Delta 近似計算。',
              bullets:['賣 CSP 常選 ITM Prob < 20% 的 Strike','約 80% 機率讓期權到期歸零，收全額權利金','直接以機率角度判斷勝率，最直觀'] },
            { num:'⑭', en:'Type',     zh:'合約類型',     color:'#64748b', example:'Put',
              summary:'標示這份合約是看漲（Call）還是看跌（Put）。',
              bullets:['Call：有權以 Strike 買入股票','Put：有權以 Strike 賣出股票','Wheel：賣 Put（CSP）被行使後再賣 Covered Call'] }
          ];

          var lastCol = -1;

          function posTip(e) {
            var x = e.clientX + 20, y = e.clientY - 20;
            var tw = tip.offsetWidth || 300, th = tip.offsetHeight || 160;
            if (x + tw > window.innerWidth  - 12) x = e.clientX - tw - 20;
            if (y + th > window.innerHeight - 12) y = window.innerHeight - th - 12;
            if (y < 8) y = 8;
            tip.style.left = x + 'px';
            tip.style.top  = y + 'px';
          }

          function fillTip(col) {
            hdr.style.background = col.color;
            num.textContent = col.num;
            en.textContent  = col.en;
            zh.textContent  = col.zh;
            ex.textContent  = col.example;
            sm.textContent  = col.summary;
            bl.innerHTML = col.bullets.map(function(b) {
              return '<p style="display:flex;gap:4px;font-size:0.85rem;color:#6b7280;line-height:1.5">' +
                '<span style="color:' + col.color + ';flex-shrink:0">›</span>' + b + '</p>';
            }).join('');
          }

          // Listen on the container — always receives events regardless of child opacity
          wrapper.style.cursor = 'crosshair';

          wrapper.addEventListener('mousemove', function(e) {
            var rect  = wrapper.getBoundingClientRect();
            var xPct  = (e.clientX - rect.left) / rect.width * 100;
            var col   = -1;
            for (var i = 0; i < BOUNDS.length - 1; i++) {
              if (xPct >= BOUNDS[i] && xPct < BOUNDS[i + 1]) { col = i; break; }
            }
            if (col < 0) {
              tip.classList.add('hidden');
              hl.style.opacity = '0';
              lastCol = -1;
              return;
            }
            // Update column highlight
            hl.style.left    = BOUNDS[col] + '%';
            hl.style.width   = (BOUNDS[col + 1] - BOUNDS[col]) + '%';
            hl.style.opacity = '1';
            // Refill only when column changes
            if (col !== lastCol) { fillTip(COLS[col]); lastCol = col; }
            tip.classList.remove('hidden');
            posTip(e);
          });

          wrapper.addEventListener('mouseleave', function() {
            tip.classList.add('hidden');
            hl.style.opacity = '0';
            lastCol = -1;
          });
        })();

        // ── Barchart (Calls+Puts) image tooltip ──
        (function () {
          var wrapper = document.getElementById('barchart-img-container');
          var tip     = document.getElementById('barchart-col-tooltip');
          var hl      = document.getElementById('barchart-col-hl');
          if (!wrapper || !tip || !hl) return;

          var hdr = document.getElementById('barchart-tt-hdr');
          var num = document.getElementById('barchart-tt-num');
          var en  = document.getElementById('barchart-tt-en');
          var zh  = document.getElementById('barchart-tt-zh');
          var ex  = document.getElementById('barchart-tt-ex');
          var sm  = document.getElementById('barchart-tt-sum');
          var bl  = document.getElementById('barchart-tt-bul');

          // Column boundaries (%) — derived from 1631px image pixel analysis
          // 20 columns: Links | Type | Latest | Bid | Ask | Change | Volume | Open Int | IV | Last Trade
          //              | Strike |
          //             Type | Latest | Bid | Ask | Change | Volume | Open Int | IV | Last Trade (Puts)
          var BOUNDS = [0, 3.7, 9.2, 17.1, 21.5, 26.4, 32.0, 39.5, 45.5, 49.6, 53.8, 58.7, 62.1, 65.8, 69.7, 73.5, 77.0, 81.0, 88.7, 92.0, 100];

          var COLS = [
            { num:'①', en:'Links', zh:'圖表連結', color:'#64748b', example:'🔗',
              summary:'每列左側的圖示連結，點擊可直接進入該合約的走勢圖或下單介面。',
              bullets:['Click → 查看單一期權的歷史 IV 走勢圖', '方便快速進入 Calls 或 Puts 的交易頁面'] },
            { num:'②', en:'Type', zh:'合約類型（Calls）', color:'#3b82f6', example:'C',
              summary:'C = Call（買權），表示這是 Calls 那一側的合約。',
              bullets:['Call 給你「以 Strike 買入股票」的權利', 'Barchart 左半部全為 Call 合約', '搭配 Strike 判斷是否在價內（ITM）'] },
            { num:'③', en:'Latest', zh:'最新成交價（Call）', color:'#3b82f6', example:'$2.05',
              summary:'這份 Call 期權最近一筆成交的市場價格。',
              bullets:['1 合約 = 100 股，實際費用 = Latest × 100', '流動性差時 Latest 可能遠離中間報價', '搭配 Bid/Ask 確認成交是否合理'] },
            { num:'④', en:'Bid', zh:'買入出價（Call）', color:'#3b82f6', example:'$1.90',
              summary:'市場上最高的買入報價（做市商願意以此價格收購你的合約）。',
              bullets:['賣出合約時通常以 Bid 成交', 'Bid 越接近 Ask 代表流動性越好', 'Bid/Ask 差大時實際進出成本高'] },
            { num:'⑤', en:'Ask', zh:'賣出要價（Call）', color:'#3b82f6', example:'$2.10',
              summary:'市場上最低的賣出報價（需支付此價格才能買入合約）。',
              bullets:['買入合約時通常以 Ask 成交', '中間價 Mid = (Bid + Ask) / 2，可嘗試掛在此', 'Ask 遠高於 Bid → 流動性差，避免市價單'] },
            { num:'⑥', en:'Change', zh:'價格變動（Call）', color:'#f59e0b', example:'+$0.15',
              summary:'相對前一交易日收盤價的漲跌幅。',
              bullets:['正值（綠色）= Call 漲價，隱含 IV 或股價走高', '負值（紅色）= Call 跌價，股價下跌或 IV 壓縮', '觀察 Change 可判斷市場方向情緒'] },
            { num:'⑦', en:'Volume', zh:'當日成交量（Call）', color:'#0ea5e9', example:'230',
              summary:'今日這份 Call 合約的成交總量（合約數）。',
              bullets:['Volume 高 → 市場活躍，Bid/Ask 差窄', 'Volume 低 → 流動性差，避免大量進出', '突然大量 Volume → 可能有機構佈局或消息面'] },
            { num:'⑧', en:'Open Int', zh:'未平倉量（Call）', color:'#0ea5e9', example:'1,820',
              summary:'目前市場上這份 Call 合約尚未結算的總量。',
              bullets:['Open Int 大 → 流動性好，容易找到對手盤', '搭配 Volume 一起看：Volume 遠大於 OI 代表今天進了大量新倉', '減少代表有人平倉或合約到期'] },
            { num:'⑨', en:'IV', zh:'隱含波動率（Call）', color:'#f59e0b', example:'58.3%',
              summary:'這份 Call 合約的隱含波動率，由市場價格反推而來。',
              bullets:['IV 高 → 合約偏貴，賣 Covered Call 有利', 'ATM 附近 IV 最低；深 ITM / OTM 的 IV 會偏高（IV Skew）', '與 HV 比較：IV > HV → 賣方有優勢'] },
            { num:'⑩', en:'Last Trade', zh:'最後成交時間（Call）', color:'#64748b', example:'05/13 10:32',
              summary:'這份 Call 合約最近一次成交的日期與時間。',
              bullets:['時間久遠代表流動性差、很久沒有成交', '配合 Volume 判斷：Low Volume + 舊 Last Trade = 避開', '活絡合約通常當天就有多筆成交'] },
            { num:'⑪', en:'Strike', zh:'行權價（中央軸）', color:'#7c3aed', example:'$80.00',
              summary:'這列期權的行權價，是 Calls 與 Puts 共用的核心基準價格。',
              bullets:['股價 > Strike → Call ITM（有內在價值）', '股價 < Strike → Put ITM（有內在價值）', 'ATM Strike 是波動率最集中的區域，也是 Wheel 策略最常選擇的位置'] },
            { num:'⑫', en:'Type', zh:'合約類型（Puts）', color:'#ef4444', example:'P',
              summary:'P = Put（賣權），表示這是 Puts 那一側的合約。',
              bullets:['Put 給你「以 Strike 賣出股票」的權利', 'Barchart 右半部全為 Put 合約', 'Wheel 的 CSP（現金擔保賣權）即是賣出 Put'] },
            { num:'⑬', en:'Latest', zh:'最新成交價（Put）', color:'#ef4444', example:'$1.85',
              summary:'這份 Put 期權最近一筆成交的市場價格。',
              bullets:['Put Latest 通常隨股價下跌而上漲', '1 合約 = 100 股，Wheel 收到的權利金 = Latest × 100', '流動性差時避免市價單'] },
            { num:'⑭', en:'Bid', zh:'買入出價（Put）', color:'#ef4444', example:'$1.75',
              summary:'市場最高買入報價，賣出 Put 時通常以此成交。',
              bullets:['賣 CSP 時以 Bid 成交，實際收到的權利金', 'Bid/Ask 差越小越好，進出成本低', '可嘗試掛 Mid 價，通常也能成交'] },
            { num:'⑮', en:'Ask', zh:'賣出要價（Put）', color:'#ef4444', example:'$1.95',
              summary:'市場最低賣出報價，買入 Put 時需支付此價格。',
              bullets:['保護性買 Put（Protective Put）用 Ask 進場', 'Bid/Ask 差大的 Put → 流動性差，避免買入', 'Mid = (Bid+Ask)/2 是最佳掛單目標'] },
            { num:'⑯', en:'Change', zh:'價格變動（Put）', color:'#f59e0b', example:'-$0.10',
              summary:'Put 合約相對前一交易日的價格變化。',
              bullets:['股價下跌時 Put 通常漲價（負 Change 代表股價漲）', '觀察 Put Change 可判斷市場對下行風險的憂慮程度', '財報前後 Put Change 常非常劇烈'] },
            { num:'⑰', en:'Volume', zh:'當日成交量（Put）', color:'#0ea5e9', example:'520',
              summary:'今日這份 Put 合約的成交總量。',
              bullets:['Put Volume 暴增可能反映大戶買保護或押注下跌', '與 Call Volume 比較：Put/Call Ratio 是市場情緒指標', 'Wheel 賣 CSP 選擇 Volume > 100 的合約較安全'] },
            { num:'⑱', en:'Open Int', zh:'未平倉量（Put）', color:'#0ea5e9', example:'3,240',
              summary:'這份 Put 合約目前未平倉的總合約數。',
              bullets:['Open Int 大 → 流動性好，容易以合理價成交', '選 CSP 執行價時常參考 Open Int 找支撐位', '大量 Open Int 聚集的 Strike 常形成支撐或阻力'] },
            { num:'⑲', en:'IV', zh:'隱含波動率（Put）', color:'#f59e0b', example:'61.2%',
              summary:'這份 Put 的隱含波動率，反映市場對下行風險的定價。',
              bullets:['Put IV 通常略高於 Call IV（Skew 效應）', 'Put IV 越高 → CSP 權利金越豐厚', 'IV 高位（IVR > 60%）賣 Put 是 Wheel 黃金時機'] },
            { num:'⑳', en:'Last Trade', zh:'最後成交時間（Put）', color:'#64748b', example:'05/13 09:45',
              summary:'這份 Put 合約最近一次成交的時間。',
              bullets:['時間久遠 = 流動性差，賣出時難找買家', 'Wheel 選 CSP 要選當天有成交紀錄的 Strike', '配合 Volume / Open Int 三項合一判斷流動性'] }
          ];

          var lastCol = -1;

          function posTip2(e) {
            var x = e.clientX + 20, y = e.clientY - 20;
            var tw = tip.offsetWidth || 320, th = tip.offsetHeight || 180;
            if (x + tw > window.innerWidth  - 12) x = e.clientX - tw - 20;
            if (y + th > window.innerHeight - 12) y = window.innerHeight - th - 12;
            if (y < 8) y = 8;
            tip.style.left = x + 'px';
            tip.style.top  = y + 'px';
          }

          function fillTip2(col) {
            hdr.style.background = col.color;
            num.textContent = col.num;
            en.textContent  = col.en;
            zh.textContent  = col.zh;
            ex.textContent  = col.example;
            sm.textContent  = col.summary;
            bl.innerHTML = col.bullets.map(function(b) {
              return '<p style="display:flex;gap:4px;font-size:0.85rem;color:#6b7280;line-height:1.5">' +
                '<span style="color:' + col.color + ';flex-shrink:0">›</span>' + b + '</p>';
            }).join('');
          }

          wrapper.style.cursor = 'crosshair';

          wrapper.addEventListener('mousemove', function(e) {
            var rect = wrapper.getBoundingClientRect();
            var xPct = (e.clientX - rect.left) / rect.width * 100;
            var col  = -1;
            for (var i = 0; i < BOUNDS.length - 1; i++) {
              if (xPct >= BOUNDS[i] && xPct < BOUNDS[i + 1]) { col = i; break; }
            }
            if (col < 0) {
              tip.classList.add('hidden');
              hl.style.opacity = '0';
              lastCol = -1;
              return;
            }
            hl.style.left    = BOUNDS[col] + '%';
            hl.style.width   = (BOUNDS[col + 1] - BOUNDS[col]) + '%';
            hl.style.opacity = '1';
            if (col !== lastCol) { fillTip2(COLS[col]); lastCol = col; }
            tip.classList.remove('hidden');
            posTip2(e);
          });

          wrapper.addEventListener('mouseleave', function() {
            tip.classList.add('hidden');
            hl.style.opacity = '0';
            lastCol = -1;
          });
        })();
      JS
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
