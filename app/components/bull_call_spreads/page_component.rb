# frozen_string_literal: true

module BullCallSpreads
end

# bcvs.md §功能流程：單頁步驟式 UI。Step1 代號 → Step2 到期日 → Step3 K1 下拉
# → 三 tab K2 建議（保守/平衡/積極）→ 口數 → 修復模式（選配）→ 說明表格。
# 抓取（到期日、Call 鏈）都要打 CDP，走 job+輪詢+整頁重載（比照
# BullPutSpreads::PageComponent 的模式）；K2 建議與修復模式計算不碰 CDP，走
# 同步 fetch，不整頁重載。
class BullCallSpreads::PageComponent < ApplicationComponent
  def initialize(symbol: nil, symbol_error: nil, scrape_status: nil, expirations: nil,
                 underlying_price: nil, summary: nil, expiration: nil, chain_status: nil,
                 call_chain: nil, k1: nil)
    @symbol           = symbol
    @symbol_error     = symbol_error
    @scrape_status    = scrape_status
    @expirations      = Array(expirations)
    @underlying_price = underlying_price
    @summary          = summary || {}
    @expiration       = expiration
    @chain_status     = chain_status
    @call_chain       = Array(call_chain).sort_by { |r| r["strike"].to_f }
    @k1               = k1
  end

  def view_template
    div(class: "space-y-6") do
      render_level3_banner
      div(class: "flex items-start justify-between gap-3") do
        render_header
        render_tour_button
      end
      render_symbol_form
      render_progress_bar
      render_symbol_error if @symbol_error
      render_expiration_section if @symbol
      render_chain_section if @expiration && @chain_status
      render_notes
      render_repair_panel if @expiration && @chain_status
    end
    render_font_face_style
    render_tooltips_script
    render_script
  end

  private

  # ---------------------------------------------------------------------------
  # Header / Level 3 banner / Step1
  # ---------------------------------------------------------------------------
  # bcvs.md §視覺規範：紅色字＝虧損金額與關鍵警語（如 Level 3、鎖定虧損）。
  def render_level3_banner
    div(id: "bcvs-level3-banner", class: "px-4 py-2 bg-[#FDEAEA] border-[1.5px] border-[#F5AAAA] rounded-[10px]") do
      span(class: "text-red-600 font-semibold text-[20px]") do
        plain "⚠️ 本策略含賣出期權腳，需三級（Level 3）期權交易權限方可開設"
      end
    end
  end

  def render_header
    div do
      h1(class: "text-[24px] font-bold text-gray-900") { plain "牛市看漲價差試算" }
      p(class: "text-[20px] text-gray-500 mt-0.5") do
        plain "Bull Call Vertical Spread · K1 買、K2 賣，debit 建倉 · 最大損失 = 淨成本 × 100"
      end
    end
  end

  # bcvs.md §導覽與欄位說明規範 B：9 步全頁導覽，右上角按鈕啟動。步驟數固定 9，
  # 與頁面當下狀態無關（元素不存在時 JS 端 filter 掉，不強制報錯，讓使用者
  # 在任何階段都能點——即使還沒選 K1，仍可看到已存在的步驟）。
  TOUR_STEPS = [
    { key: "symbol",   el: "#bcvs-symbol-input",     title: "① 股票代號",       desc: "輸入標的代號，查詢已開設的期權到期日清單。" },
    { key: "expiration", el: "#bcvs-expiration-section", title: "② 到期日",     desc: "選擇同到期日的 Call chain，K1/K2 必須來自同一個到期日。" },
    { key: "k1",       el: "#bcvs-k1-select",         title: "③ K1（買進，Long Call）", desc: "選擇履約價較低的買進腳，系統會以此計算 K2 建議。" },
    { key: "tabs",     el: "#bcvs-recommend-tabs",     title: "④ 三檔 K2 建議",   desc: "保守/平衡/積極三個 tab，依 debit÷價差寬度 比值挑選賣出腳 K2。" },
    { key: "interval", el: "#bcvs-interval-card",      title: "⑤ 損益區間表",    desc: "到期股價落在哪個區間、賠多少賺多少，一律以即時數字呈現。" },
    { key: "naked",    el: "#bcvs-naked-card",         title: "⑥ 裸買對照表",    desc: "跟只買 K1 單腳比較成本與獲利，並算出到期損益交叉價 S*。" },
    { key: "early_close", el: "#bcvs-early-close-card", title: "⑦ 提前平倉指引", desc: "不必等到期，現在平倉可收回多少、已實現獲利比例 Y 是否達 80% 建議了結。" },
    { key: "repair",   el: "#bcvs-repair-panel",       title: "⑧ 修復模式",      desc: "已持有 K1 長倉（如虧損中的 LEAPS）時，填入實際成本重新試算鎖定結果。" },
    { key: "level3",   el: "#bcvs-level3-banner",      title: "⑨ Level 3 權限提醒", desc: "本策略含賣出期權腳，下單前務必確認帳戶已有三級期權交易權限。" }
  ].freeze

  def render_tour_button
    button(id: "bcvs-tour-btn", type: "button",
           class: "flex-shrink-0 px-3 py-1.5 text-[20px] font-medium rounded-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 whitespace-nowrap") do
      plain "導覽"
    end
  end

  def render_symbol_form
    form(id: "bcvs-symbol-form", action: bull_call_spreads_path, method: "get",
         class: "flex items-center gap-2") do
      input(type: "text", id: "bcvs-symbol-input", name: "symbol",
            value: @symbol.to_s, placeholder: "股票代號，例如 NOK",
            maxlength: 6, autocomplete: "off",
            class: "px-3 py-2 border border-gray-300 rounded-lg text-[20px] w-48 uppercase")
      button(type: "submit", id: "bcvs-submit-btn",
             class: "px-4 py-2 bg-blue-600 text-white text-[20px] font-medium rounded-lg hover:bg-blue-700") do
        plain "查詢到期日"
      end
      span(id: "bcvs-loading", class: "hidden text-[20px] text-blue-600 animate-pulse") { plain "抓取中…" }
    end
  end

  def render_progress_bar
    div(id: "bcvs-progress", class: "hidden h-1.5 w-full bg-gray-100 rounded-full overflow-hidden") do
      div(id: "bcvs-progress-fill", class: "h-full w-1/3 bg-blue-500 rounded-full bcvs-progress-anim")
    end
  end

  def render_symbol_error
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-[20px] rounded-lg") do
      plain "⚠️ #{@symbol_error}"
    end
  end

  # ---------------------------------------------------------------------------
  # Step2：到期日
  # ---------------------------------------------------------------------------
  def render_expiration_section
    div(id: "bcvs-expiration-section", class: "space-y-2") do
      h2(class: "text-[20px] font-semibold text-gray-700") { plain "Step 2 · 選擇到期日" }

      case @scrape_status
      when :cached
        div(class: "space-y-3") do
          if @underlying_price
            p(class: "text-[20px] text-gray-500") { plain "現價 $#{sprintf("%.2f", @underlying_price.to_f)}" }
          end
          div(class: "flex justify-center") { render_underlying_summary_card }
          div(class: "flex flex-wrap gap-2") do
            @expirations.each do |exp|
              active = exp[:value] == @expiration
              btn_class = active ?
                "px-3 py-1.5 rounded-lg text-[20px] font-medium bg-blue-600 text-white" :
                "px-3 py-1.5 rounded-lg text-[20px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400"
              button(type: "button", class: btn_class, data: { exp: exp[:value], "bcvs-expiration-btn": "" }) do
                plain exp[:label]
              end
            end
          end
        end
      when :ready_to_fetch
        p(class: "text-[20px] text-gray-500") { plain "尚未抓取，請按下方按鈕從 Barchart 讀取到期日清單" }
        button(type: "button", id: "bcvs-fetch-expirations-btn",
               class: "px-3 py-1.5 bg-blue-600 text-white text-[20px] font-medium rounded-lg hover:bg-blue-700") do
          plain "抓取到期日"
        end
      when :session_expired
        render_status_alert("Barchart 登入已過期，請重新登入後重試")
      when :cdp_offline
        render_status_alert("CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動")
      when :no_candidates
        render_status_alert("找不到到期日，請確認代號是否有期權交易")
      else
        render_status_alert("抓取失敗，請稍後重試")
      end
    end
  end

  def render_status_alert(msg)
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-[20px] rounded-lg") { plain "⚠️ #{msg}" }
  end

  # bcvs.md §功能流程 步驟1（v4）：標的摘要五值，顯示於「現價」與到期日
  # 按鈕之間（v4.1 依使用者截圖回饋，從側邊改置中），v3 卡片樣式（沿用同一套
  # 圓角/邊框語彙，中性色—不佔用三張分析卡的固定色碼）。五列皆附 tooltip。
  def render_underlying_summary_card
    return if @summary.blank?

    div(class: "w-full sm:w-96 rounded-xl overflow-hidden border bcvs-notosans bcvs-card-neutral") do
      div(class: "flex items-center gap-2 px-4 py-2.5 bcvs-band-neutral") do
        span(class: "bcvs-band-label") { plain "標的摘要" }
      end
      div(class: "p-4 space-y-1.5 bcvs-body bcvs-body-neutral") do
        render_summary_row("現價", price_change_text)
        render_summary_row("Latest Earnings", @summary[:latest_earnings] || "—", tip_key: "summary_earnings")
        render_summary_row("IV (ATM)", pct_text(@summary[:iv_atm]), tip_key: "summary_iv_atm")
        render_summary_row("HV", pct_text(@summary[:hv]), tip_key: "summary_hv")
        render_summary_row("IV Rank", pct_text(@summary[:iv_rank]), tip_key: "summary_iv_rank")
      end
    end
  end

  def render_summary_row(label, value, tip_key: nil)
    div(class: "flex items-center justify-between gap-2") do
      span(class: "text-gray-500", data_tip_key: tip_key) { plain label }
      span(class: "font-semibold") { plain value }
    end
  end

  def price_change_text
    return "—" if @underlying_price.blank?
    text = "$#{sprintf("%.2f", @underlying_price.to_f)}"
    change = @summary[:price_change]
    text += " (#{change >= 0 ? "+" : ""}#{sprintf("%.2f", change)})" if change.present?
    text
  end

  def pct_text(value)
    value.present? ? "#{sprintf("%.1f", value)}%" : "—"
  end

  # ---------------------------------------------------------------------------
  # Step3：Call 鏈 + K1 下拉 + Step4：三 tab K2 建議 + Step5：口數/計算結果
  # ---------------------------------------------------------------------------
  def render_chain_section
    div(class: "space-y-4") do
      case @chain_status
      when :cached
        render_chain_block
      when :session_expired
        render_status_alert("Barchart 登入已過期，請重新登入後重試")
      when :cdp_offline
        render_status_alert("CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動")
      when :no_candidates
        render_status_alert("此到期日無可用的 Call 報價")
      when :ready_to_fetch
        p(class: "text-[20px] text-gray-500") { plain "正在抓取 #{@expiration} 的 Call 鏈…" }
      else
        render_status_alert("抓取失敗，請稍後重試")
      end
    end
  end

  COLUMNS = [
    { key: "strike",        label: "價格",      align: "text-left" },
    { key: "moneyness",     label: "Moneyness", align: "text-right" },
    { key: "bid",           label: "Bid",       align: "text-right" },
    { key: "mid",           label: "Mid",       align: "text-right" },
    { key: "ask",           label: "Ask",       align: "text-right" },
    { key: "last",          label: "Last",      align: "text-right" },
    { key: "change",        label: "Change",    align: "text-right" },
    { key: "pct_change",    label: "%Change",   align: "text-right" },
    { key: "volume",        label: "Volume",    align: "text-right" },
    { key: "open_interest", label: "OI",        align: "text-right" },
    { key: "oi_change",     label: "OI Chg",    align: "text-right" },
    { key: "iv",            label: "IV",        align: "text-right" },
    { key: "delta",         label: "Delta",     align: "text-right" }
  ].freeze

  COLUMN_EXPLAIN = {
    "strike" => {
      title: "履約價（Strike）",
      desc: "選擇權合約約定的履約價格。K1（買進，Long Call）取 Ask、K2（賣出，Short Call）取 Bid，K2−K1 即為價差寬度。"
    },
    # bcvs.md §導覽與欄位說明規範 A：以下 desc 為規格固定文案（逐字），
    # 不得改寫；BID/MID/ASK 與 CHANGE/%CHANGE 各自共用同一段文字。
    "moneyness" => {
      title: "Moneyness（價內外程度）",
      desc: "價內程度：股價相對履約價的位置，越高越深價內"
    },
    "bid" => {
      title: "Bid（買方出價）",
      desc: "買價／中間價／賣價；本工具 K1 以 ask、K2 以 bid 保守計價"
    },
    "mid" => {
      title: "Mid（中價）",
      desc: "買價／中間價／賣價；本工具 K1 以 ask、K2 以 bid 保守計價"
    },
    "ask" => {
      title: "Ask（賣方要價）",
      desc: "買價／中間價／賣價；本工具 K1 以 ask、K2 以 bid 保守計價"
    },
    "last" => {
      title: "Last（最後成交價）",
      desc: "最近成交價（可能過時，以 bid/ask 為準）"
    },
    "change" => {
      title: "Change（漲跌）",
      desc: "當日漲跌（金額／百分比）"
    },
    "pct_change" => {
      title: "%Change（漲跌幅）",
      desc: "當日漲跌（金額／百分比）"
    },
    "volume" => {
      title: "Volume（成交量）",
      desc: "當日成交口數"
    },
    "open_interest" => {
      title: "OI（未平倉量）",
      desc: "未平倉量：流動性指標，0 代表無人持倉、勿選"
    },
    "oi_change" => {
      title: "OI Chg（未平倉量變化）",
      desc: "未平倉量變化"
    },
    "iv" => {
      title: "IV（隱含波動率）",
      desc: "隱含波動率：越高權利金越貴"
    },
    "delta" => {
      title: "Delta（避險比率）",
      desc: "對沖比率：可近似解讀為到期價內機率"
    },
    # bcvs.md §功能流程 步驟1（v4）：標的摘要表 tooltip，Latest Earnings／
    # IV Rank 為規格固定文案，IV(ATM)／HV 為後續使用者回饋補上（同一套語感）。
    "summary_earnings" => {
      title: "Latest Earnings",
      desc: "BMO＝Before Market Open（盤前公布）；AMC＝After Market Close（盤後公布）。財報日前 IV 通常走高、公布後常見 IV crush，建倉時點宜避開財報前的高權利金"
    },
    "summary_iv_atm" => {
      title: "IV (ATM)",
      desc: "價平（At-The-Money）隱含波動率：市場對這檔標的近期波動幅度的預期，數字越高權利金越貴，debit 價差建倉成本越高"
    },
    "summary_hv" => {
      title: "HV（歷史波動率）",
      desc: "這檔標的近期實際股價波動幅度。IV 明顯高於 HV 代表市場預期波動即將放大（如財報前），此時買方腳（K1）成本偏貴"
    },
    "summary_iv_rank" => {
      title: "IV Rank",
      desc: "IV Rank 高＝權利金貴，debit 價差成本升高"
    }
  }.freeze

  def render_chain_block
    div(class: "space-y-2") do
      h2(class: "text-[20px] font-semibold text-gray-700") { plain "Step 3 · 選擇 K1（買進，Long Call）" }
      p(class: "text-[20px] text-gray-500") do
        plain "保守計價：K1 取 ask、K2 取 bid，以最不利成交價估算，實際可用 mid 價掛單"
      end
      render_k1_select
      render_recommend_tabs
      div(class: "w-full overflow-x-auto border border-gray-200 rounded-lg") do
        table(id: "bcvs-chain-table", class: "min-w-full text-[20px] whitespace-nowrap") do
          thead(class: "bg-gray-50 text-gray-500 uppercase") do
            tr do
              COLUMNS.each do |col|
                th(id: "bcvs-th-#{col[:key]}", data_tip_key: col[:key],
                   class: "px-2 py-1.5 #{col[:align]}") { plain col[:label] }
              end
            end
          end
          tbody do
            @call_chain.each_with_index { |row, i| render_chain_row(row, i) }
          end
        end
      end
    end
  end

  def render_k1_select
    div(class: "flex items-center gap-2") do
      label(class: "text-[20px] text-gray-600", for: "bcvs-k1-select") { plain "K1 履約價" }
      select(id: "bcvs-k1-select", class: "border border-gray-300 rounded px-2 py-1.5 text-[20px]") do
        option(value: "") { plain "請選擇" }
        @call_chain.each do |row|
          next if row["ask"].nil?
          strike = row["strike"].to_f
          selected = @k1.present? && @k1.to_f == strike
          option(value: strike, selected: selected, data: { ask: row["ask"], bid: row["bid"] }) do
            plain "$#{sprintf("%.2f", strike)}（ask #{sprintf("%.2f", row["ask"].to_f)}）"
          end
        end
      end
    end
  end

  def render_recommend_tabs
    div(id: "bcvs-recommend-tabs", class: "hidden space-y-3") do
      div(class: "flex items-center gap-2 mt-2") do
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[20px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
               data: { "bcvs-recommend-tab": "conservative" }) { plain "保守" }
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[20px] font-medium bg-blue-600 text-white border border-blue-600",
               data: { "bcvs-recommend-tab": "balanced" }) { plain "平衡" }
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[20px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
               data: { "bcvs-recommend-tab": "aggressive" }) { plain "積極" }
      end
      div(id: "bcvs-recommend-error", class: "hidden px-3 py-2 bg-red-50 border border-red-200 text-red-700 text-[20px] rounded-lg")
      render_calc_panel
      render_interval_table
      render_naked_comparison
      render_early_close_panel
    end
  end

  # bcvs.md §字級鐵則 v4：Step 5 主數字 24px 粗體，標籤 20px。
  def render_calc_panel
    div(id: "bcvs-calc-panel", class: "space-y-3 p-4 bg-white border border-gray-200 rounded-lg") do
      div(class: "flex items-center justify-between") do
        h2(class: "text-[20px] font-semibold text-gray-700") { plain "Step 5 · 計算結果" }
        label(class: "flex items-center gap-2 text-[20px] text-gray-600") do
          plain "口數"
          input(type: "number", id: "bcvs-lots-input", value: "1", min: "1", step: "1",
                class: "w-16 border border-gray-300 rounded px-2 py-1 text-[20px] text-right")
        end
      end
      div(id: "bcvs-calc-warning", class: "hidden px-3 py-2 bg-red-50 border border-red-300 text-red-800 text-[20px] rounded-lg")
      dl(id: "bcvs-calc-grid", class: "grid grid-cols-2 sm:grid-cols-4 gap-3")
    end
  end

  # bcvs.md §視覺規範 v3（經使用者樣稿確認，固定色碼＋3D 圖示，不得另創配色）。
  # 圖示來源：Microsoft Fluent Emoji 3D（MIT License，
  # github.com/microsoft/fluentui-emoji），PNG 已下載進
  # app/assets/images/bcvs/，不熱連 CDN。
  CARD_SPECS = {
    # slug 對應 app/assets/tailwind/application.css 的 .bcvs-card-* / -band-* / -body-*，
    # 色值原封不動搬過去（CSP style-src 收斂，色碼仍受 bcvs.md §視覺規範 v3 約束）。
    interval:    { slug: "interval",    icon: "chart_increasing_3d.png",   title: "損益區間表" },
    naked:       { slug: "naked",       icon: "compass_3d.png",            title: "為什麼不直接裸買 LEAPS Call？" },
    early_close: { slug: "early-close", icon: "hourglass_not_done_3d.png", title: "提前平倉指引（不必等到期）" }
  }.freeze

  # bcvs.md §視覺規範 v3「卡片結構」：radius 12px、overflow hidden，頂部深色
  # 標題色帶（22px/500 淺色字＋24px 3D 圖示靠左）＋淺色卡身（20px 內文/表格，
  # v4 字級鐵則取代舊制 15/14px）。
  def render_v3_card(key, body_id:)
    spec = CARD_SPECS.fetch(key)
    div(id: "bcvs-#{key.to_s.tr("_", "-")}-card",
        class: "rounded-xl overflow-hidden border bcvs-notosans bcvs-card-#{spec[:slug]}") do
      div(class: "flex items-center gap-2 px-4 py-2.5 bcvs-band-#{spec[:slug]}") do
        img(src: helpers.asset_path("bcvs/#{spec[:icon]}"), class: "w-6 h-6", alt: "")
        span(class: "bcvs-band-label") { plain spec[:title] }
      end
      div(id: body_id, class: "p-4 space-y-2 bcvs-body bcvs-body-#{spec[:slug]}") do
        yield
      end
    end
  end

  # bcvs.md §損益區間表：動態，D=淨成本 debit。以實際數字渲染，不得只顯示公式
  # ——JS 依當前 tab 的 k1/k2/debit/breakeven 與現價即時算出表格內容，
  # 虧損列紅字(#A32D2D)、損平列灰字(#5F5E5A)、獲利列綠字(#3B6D11)。
  def render_interval_table
    render_v3_card(:interval, body_id: "bcvs-interval-body") do
      p(class: "font-mono font-semibold bcvs-formula-green") { plain "D = K1 ask − K2 bid" }
      p(id: "bcvs-interval-formula-example", class: "bcvs-note")
      div(id: "bcvs-interval-table")
    end
  end

  # bcvs.md §為什麼不直接裸買 LEAPS Call：對照表 + 到期損益交叉價 S*。
  def render_naked_comparison
    render_v3_card(:naked, body_id: "bcvs-naked-body") do
      p(class: "font-mono font-semibold bcvs-formula-rust") { plain "S* = K2 + K2 bid" }
      p(class: "bcvs-note") { plain "到期價 < S* 時價差策略勝出，> S* 時裸買勝出" }
      div(id: "bcvs-naked-comparison")
    end
  end

  # bcvs.md §提前平倉指引：兩個口徑（毛額現值／淨額獲利）並列，Y=已實現獲利
  # 比例=(現值−成本)÷最大獲利。
  def render_early_close_panel
    render_v3_card(:early_close, body_id: "bcvs-early-close-body") do
      p(class: "font-mono font-semibold bcvs-formula-amber") { plain "Y = (現值 − 成本) ÷ 最大獲利" }
      p(class: "bcvs-note") { plain "現值以快取 chain 保守估（K1 bid − K2 ask）；Y ≥ 80% 建議考慮獲利了結" }
      div(id: "bcvs-early-close")
    end
  end

  # ---------------------------------------------------------------------------
  # 修復模式（bcvs.md §修復模式，選配輸入）
  # ---------------------------------------------------------------------------
  def render_repair_panel
    details(id: "bcvs-repair-panel", class: "border border-gray-200 rounded-lg") do
      summary(class: "px-4 py-2 text-[20px] font-medium text-gray-700 cursor-pointer") { plain "修復模式（已持有 K1 長倉，選配）" }
      div(class: "p-4 space-y-3 border-t border-gray-100") do
        p(class: "text-[20px] text-gray-500") { plain "已持有 K1 長倉（如虧損中的 LEAPS）時填入實際進場成本，計算改用此成本取代 K1 ask" }
        div(class: "flex flex-wrap items-center gap-3") do
          label(class: "flex items-center gap-2 text-[20px]") do
            plain "第一腳成本覆寫（basis）"
            input(type: "number", id: "bcvs-repair-basis-input", step: "0.01", min: "0",
                  class: "w-24 border border-gray-300 rounded px-2 py-1 text-[20px] text-right")
          end
          label(class: "flex items-center gap-2 text-[20px]") do
            plain "K1 現價 bid（選配，用於對照平倉）"
            input(type: "number", id: "bcvs-repair-current-bid-input", step: "0.01", min: "0",
                  class: "w-24 border border-gray-300 rounded px-2 py-1 text-[20px] text-right")
          end
        end
        div(id: "bcvs-repair-result", class: "hidden space-y-1 text-[20px]")
      end
    end
  end

  def render_chain_row(row, index)
    strike = row["strike"].to_f
    row_class = (index.odd? ? "bg-gray-50/50" : "") + " border-t border-gray-100"

    data_attrs = {}
    COLUMNS.each { |col| data_attrs[col[:key].to_sym] = row[col[:key]] }
    data_attrs[:strike] = strike

    tr(id: "bcvs-row-#{strike_row_id(strike)}", class: row_class, data: data_attrs) do
      COLUMNS.each { |col| render_chain_cell(col[:key], row, strike) }
    end
  end

  def render_chain_cell(key, row, strike)
    case key
    when "strike"
      td(class: "px-4 py-2 font-medium text-gray-900") { plain sprintf("%.2f", strike) }
    when "moneyness"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["moneyness"] ? sprintf("%.2f%%", row["moneyness"].to_f * 100) : "—" }
    when "bid"
      td(class: "px-4 py-2 text-right") { plain row["bid"].nil? ? "—" : sprintf("%.2f", row["bid"].to_f) }
    when "mid"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["mid"] ? sprintf("%.2f", row["mid"].to_f) : "—" }
    when "ask"
      td(class: "px-4 py-2 text-right") { plain row["ask"].nil? ? "—" : sprintf("%.2f", row["ask"].to_f) }
    when "last"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["last"] ? sprintf("%.2f", row["last"].to_f) : "—" }
    when "change"
      render_delta_cell(row["change"]) { |v| sprintf("%+.2f", v) }
    when "pct_change"
      render_delta_cell(row["pct_change"]) { |v| sprintf("%+.2f%%", v * 100) }
    when "volume"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["volume"].nil? ? "—" : row["volume"] }
    when "open_interest"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["open_interest"].nil? ? "—" : row["open_interest"] }
    when "oi_change"
      render_delta_cell(row["oi_change"]) { |v| sprintf("%+d", v.to_i) }
    when "iv"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["iv"] ? sprintf("%.1f%%", row["iv"].to_f * 100) : "—" }
    when "delta"
      td(class: "px-4 py-2 text-right text-gray-500") { plain row["delta"] ? sprintf("%.2f", row["delta"].to_f) : "—" }
    end
  end

  # Ruby Float#to_s ("12.0") 與 JS Number 序列化("12")不一致，會讓兩端組出的
  # row id 對不上（JS 端 highlight/修復模式查表因此永遠找不到列）——固定兩位
  # 小數格式，兩端各自用同一種格式化方式組 id 就能對齊。
  def strike_row_id(strike)
    sprintf("%.2f", strike).tr(".", "_")
  end

  def render_delta_cell(value)
    if value.nil?
      td(class: "px-4 py-2 text-right text-gray-400") { plain "—" }
    elsif value.to_f.zero?
      td(class: "px-4 py-2 text-right text-gray-400") { plain "unch" }
    else
      td(class: "px-4 py-2 text-right #{change_color(value)}") { plain yield(value.to_f) }
    end
  end

  # ---------------------------------------------------------------------------
  # §說明表格（固定顯示）
  # ---------------------------------------------------------------------------
  # bcvs.md §視覺規範 v3 只為三張分析卡固定色碼；好處/注意事項沿用同一色系
  # （綠＝獲利類、金＝決策警示類）維持卡片視覺，但不強制 3D 圖示與嚴格結構。
  def render_notes
    div(class: "space-y-4") do
      div(class: "rounded-xl overflow-hidden border bcvs-notosans bcvs-card-interval") do
        div(class: "flex items-center gap-2 px-4 py-2.5 bcvs-band-interval") do
          span(class: "text-[22px]") { plain "✅" }
          span(class: "bcvs-band-label") { plain "好處" }
        end
        div(class: "p-4 bcvs-body bcvs-body-interval") do
          p do
            plain "成本低於裸買 call、最大損失封頂於淨成本、賣腳權利金部分對沖 theta、修復模式可壓縮虧損 LEAPS 在橫盤～小漲區間的損失。"
          end
        end
      end
      div(class: "rounded-xl overflow-hidden border bcvs-notosans bcvs-card-early-close") do
        div(class: "flex items-center gap-2 px-4 py-2.5 bcvs-band-early-close") do
          span(class: "text-[22px]") { plain "⚠️" }
          span(class: "bcvs-band-label") { plain "注意事項" }
        end
        div(class: "p-4 space-y-1 bcvs-body bcvs-body-early-close") do
          NOTES.each { |n| p { plain n } }
        end
      end
    end
  end

  NOTES = [
    "1. K2 以上獲利封頂（大漲行情跑輸裸買）。",
    "2. 短腳深度價內＋除息日前有提前指派風險（被指派後以長腳處理，損益不變）。",
    "3. 平倉一律用組合單兩腳同出，避免單腳滑價。",
    "4. 留意兩腳的買賣價差與流動性。",
    "5. 財報前 IV 變化影響成交價。"
  ].freeze

  # bcvs.md §視覺規範 v3「字體」：Noto Sans TC self-host 進 repo（禁 Google
  # Fonts 熱連），fallback "PingFang TC","Microsoft JhengHei"。字型檔沿用
  # LEAPS PDF 匯出已 vendor 進 vendor/assets/fonts/ 的同一份，不重新下載——
  # @font-face 的 src url 需要 Propshaft 算出的 digest 路徑，只能在
  # Ruby 端用 helpers.asset_path 產生，不能寫死在 Tailwind CLI 編譯的
  # application.css 裡（那份沒有 Rails asset pipeline 可用）。
  def render_font_face_style
    # 這一塊必須留在 Ruby 端：@font-face 的 src 需要 Propshaft 算出的 digest
    # 路徑，Tailwind CLI 編譯的 application.css 沒有 Rails asset pipeline 可用。
    #
    # 加 nonce 讓它在 style-src 收緊後仍能套用——nonce 對 <style> 區塊有效，
    # 對 style="..." 屬性無效，這是 style-src 收斂最容易誤解的一點。
    style(nonce: helpers.content_security_policy_nonce) { raw <<~CSS.html_safe }
      @font-face {
        font-family: 'Noto Sans TC';
        src: url('#{helpers.asset_path("NotoSansTC-Regular-subset-v39.ttf")}') format('truetype');
        font-weight: 400;
        font-display: swap;
      }
      .bcvs-notosans, .bcvs-notosans * {
        font-family: 'Noto Sans TC', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
      }
    CSS
  end

  # ---------------------------------------------------------------------------
  # 選 K1 hover 高亮（沿用 bpus 的 phase class 機制，這裡只有一個選取階段）
  # ---------------------------------------------------------------------------

  def render_tooltips_script
    tooltips_script_js
  end

  def tooltips_script_js
    # JavaScript 已搬到 app/frontend/behaviors/bullCallTooltips.js（稽核 H-3 Wave 3）。
    # 路由與頁面狀態改用 data-config JSON 傳入（保留 null 與數值型別）。
    div(
      data: {
        behavior: "bull-call-tooltips",
        config:   {
          symbol:          @symbol,
          expiration:      @expiration,
          underlyingPrice: @underlying_price,
          colExplain:      JSON.parse(bcvs_col_explain_json),
          tourSteps:       JSON.parse(bcvs_tour_steps_json),
          routes:          {
            index:            bull_call_spreads_path,
            status:           bull_call_spreads_status_path,
            fetchExpirations: bull_call_spreads_fetch_expirations_path,
            fetchChain:       bull_call_spreads_fetch_chain_path,
            recommend:        bull_call_spreads_recommend_path,
            calculate:        bull_call_spreads_calculate_path
          }
        }.to_json
      }
    )
  end

  def bcvs_col_explain_json
    COLUMN_EXPLAIN.transform_values { |v| { title: v[:title], desc: v[:desc] } }.to_json
  end

  def bcvs_tour_steps_json
    TOUR_STEPS.map { |s| { el: s[:el], title: s[:title], desc: s[:desc] } }.to_json
  end

  # ---------------------------------------------------------------------------
  # JS：fetch_expirations / fetch_chain job 輪詢 + K1 選取 + recommend/calculate
  # ---------------------------------------------------------------------------
  def render_script
    script_js
  end

  def script_js
    # JavaScript 已搬到 app/frontend/behaviors/bullCallSpreads.js（稽核 H-3 Wave 3）。
    # 路由與頁面狀態改用 data-config JSON 傳入（保留 null 與數值型別）。
    div(
      data: {
        behavior: "bull-call-spreads",
        config:   {
          symbol:          @symbol,
          expiration:      @expiration,
          underlyingPrice: @underlying_price,
          colExplain:      JSON.parse(bcvs_col_explain_json),
          tourSteps:       JSON.parse(bcvs_tour_steps_json),
          routes:          {
            index:            bull_call_spreads_path,
            status:           bull_call_spreads_status_path,
            fetchExpirations: bull_call_spreads_fetch_expirations_path,
            fetchChain:       bull_call_spreads_fetch_chain_path,
            recommend:        bull_call_spreads_recommend_path,
            calculate:        bull_call_spreads_calculate_path
          }
        }.to_json
      }
    )
  end
end
