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
                 underlying_price: nil, expiration: nil, chain_status: nil, call_chain: nil, k1: nil)
    @symbol           = symbol
    @symbol_error     = symbol_error
    @scrape_status    = scrape_status
    @expirations      = Array(expirations)
    @underlying_price = underlying_price
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
    render_hover_style
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
      span(class: "text-red-600 font-semibold text-xs") do
        plain "⚠️ 本策略含賣出期權腳，需三級（Level 3）期權交易權限方可開設"
      end
    end
  end

  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") { plain "牛市看漲價差試算" }
      p(class: "text-[26px] text-gray-500 mt-0.5") do
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
           class: "flex-shrink-0 px-3 py-1.5 text-xs font-medium rounded-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 whitespace-nowrap") do
      plain "導覽"
    end
  end

  def render_symbol_form
    form(id: "bcvs-symbol-form", action: bull_call_spreads_path, method: "get",
         class: "flex items-center gap-2") do
      input(type: "text", id: "bcvs-symbol-input", name: "symbol",
            value: @symbol.to_s, placeholder: "股票代號，例如 NOK",
            maxlength: 6, autocomplete: "off",
            class: "px-3 py-2 border border-gray-300 rounded-lg text-sm w-48 uppercase")
      button(type: "submit", id: "bcvs-submit-btn",
             class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700") do
        plain "查詢到期日"
      end
      span(id: "bcvs-loading", class: "hidden text-xs text-blue-600 animate-pulse") { plain "抓取中…" }
    end
  end

  def render_progress_bar
    div(id: "bcvs-progress", class: "hidden h-1.5 w-full bg-gray-100 rounded-full overflow-hidden") do
      div(id: "bcvs-progress-fill", class: "h-full w-1/3 bg-blue-500 rounded-full bcvs-progress-anim")
    end
  end

  def render_symbol_error
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg") do
      plain "⚠️ #{@symbol_error}"
    end
  end

  # ---------------------------------------------------------------------------
  # Step2：到期日
  # ---------------------------------------------------------------------------
  def render_expiration_section
    div(id: "bcvs-expiration-section", class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 2 · 選擇到期日" }

      case @scrape_status
      when :cached
        if @underlying_price
          p(class: "text-xs text-gray-500") { plain "現價 $#{sprintf("%.2f", @underlying_price.to_f)}" }
        end
        div(class: "flex flex-wrap gap-2") do
          @expirations.each do |exp|
            active = exp[:value] == @expiration
            btn_class = active ?
              "px-3 py-1.5 rounded-lg text-xs font-medium bg-blue-600 text-white" :
              "px-3 py-1.5 rounded-lg text-xs font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400"
            button(type: "button", class: btn_class, data: { exp: exp[:value], "bcvs-expiration-btn": "" }) do
              plain exp[:label]
            end
          end
        end
      when :ready_to_fetch
        p(class: "text-sm text-gray-500") { plain "尚未抓取，請按下方按鈕從 Barchart 讀取到期日清單" }
        button(type: "button", id: "bcvs-fetch-expirations-btn",
               class: "px-3 py-1.5 bg-blue-600 text-white text-xs font-medium rounded-lg hover:bg-blue-700") do
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
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg") { plain "⚠️ #{msg}" }
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
        p(class: "text-sm text-gray-500") { plain "正在抓取 #{@expiration} 的 Call 鏈…" }
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
    }
  }.freeze

  def render_chain_block
    div(class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 3 · 選擇 K1（買進，Long Call）" }
      p(class: "text-[26px] text-gray-500") do
        plain "保守計價：K1 取 ask、K2 取 bid，以最不利成交價估算，實際可用 mid 價掛單"
      end
      render_k1_select
      render_recommend_tabs
      div(class: "w-full overflow-x-auto border border-gray-200 rounded-lg") do
        table(id: "bcvs-chain-table", class: "min-w-full text-xs whitespace-nowrap") do
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
      label(class: "text-[24px] text-gray-600", for: "bcvs-k1-select") { plain "K1 履約價" }
      select(id: "bcvs-k1-select", class: "border border-gray-300 rounded px-2 py-1.5 text-sm") do
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
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[24px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
               data: { "bcvs-recommend-tab": "conservative" }) { plain "保守" }
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[24px] font-medium bg-blue-600 text-white border border-blue-600",
               data: { "bcvs-recommend-tab": "balanced" }) { plain "平衡" }
        button(type: "button", class: "px-3 py-1.5 rounded-lg text-[24px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
               data: { "bcvs-recommend-tab": "aggressive" }) { plain "積極" }
      end
      div(id: "bcvs-recommend-error", class: "hidden px-3 py-2 bg-red-50 border border-red-200 text-red-700 text-[24px] rounded-lg")
      render_calc_panel
      render_interval_table
      render_naked_comparison
      render_early_close_panel
    end
  end

  def render_calc_panel
    div(id: "bcvs-calc-panel", class: "space-y-3 p-4 bg-white border border-gray-200 rounded-lg") do
      div(class: "flex items-center justify-between") do
        h2(class: "text-sm font-semibold text-gray-700") { plain "Step 5 · 計算結果" }
        label(class: "flex items-center gap-2 text-[24px] text-gray-600") do
          plain "口數"
          input(type: "number", id: "bcvs-lots-input", value: "1", min: "1", step: "1",
                class: "w-16 border border-gray-300 rounded px-2 py-1 text-right")
        end
      end
      div(id: "bcvs-calc-warning", class: "hidden px-3 py-2 bg-red-50 border border-red-300 text-red-800 text-[24px] rounded-lg")
      dl(id: "bcvs-calc-grid", class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-[24px]")
    end
  end

  # bcvs.md §視覺規範 v3（經使用者樣稿確認，固定色碼＋3D 圖示，不得另創配色）。
  # 圖示來源：Microsoft Fluent Emoji 3D（MIT License，
  # github.com/microsoft/fluentui-emoji），PNG 已下載進
  # app/assets/images/bcvs/，不熱連 CDN。
  CARD_SPECS = {
    interval: {
      band_bg: "#3B6D11", band_text: "#EAF3DE", body_bg: "#EAF3DE", border: "#97C459",
      icon: "chart_increasing_3d.png", title: "損益區間表"
    },
    naked: {
      band_bg: "#993C1D", band_text: "#FAECE7", body_bg: "#FAECE7", border: "#F0997B",
      icon: "compass_3d.png", title: "為什麼不直接裸買 LEAPS Call？"
    },
    early_close: {
      band_bg: "#854F0B", band_text: "#FAEEDA", body_bg: "#FAEEDA", border: "#EF9F27",
      icon: "hourglass_not_done_3d.png", title: "提前平倉指引（不必等到期）"
    }
  }.freeze

  # bcvs.md §視覺規範 v3「卡片結構」：radius 12px、overflow hidden，頂部深色
  # 標題色帶（15px/500 淺色字＋24px 3D 圖示靠左）＋淺色卡身（14px 內文/表格）。
  def render_v3_card(key, body_id:)
    spec = CARD_SPECS.fetch(key)
    div(id: "bcvs-#{key.to_s.tr("_", "-")}-card",
        class: "rounded-xl overflow-hidden border bcvs-notosans", style: "border-color:#{spec[:border]}") do
      div(class: "flex items-center gap-2 px-4 py-2.5", style: "background:#{spec[:band_bg]}") do
        img(src: helpers.asset_path("bcvs/#{spec[:icon]}"), class: "w-6 h-6", alt: "")
        span(style: "color:#{spec[:band_text]}; font-size:15px; font-weight:500;") { plain spec[:title] }
      end
      div(id: body_id, class: "p-4 space-y-2", style: "background:#{spec[:body_bg]}; font-size:14px; color:#2A1A0E;") do
        yield
      end
    end
  end

  # bcvs.md §損益區間表：動態，D=淨成本 debit。以實際數字渲染，不得只顯示公式
  # ——JS 依當前 tab 的 k1/k2/debit/breakeven 與現價即時算出表格內容，
  # 虧損列紅字(#A32D2D)、損平列灰字(#5F5E5A)、獲利列綠字(#3B6D11)。
  def render_interval_table
    render_v3_card(:interval, body_id: "bcvs-interval-body") do
      p(class: "font-mono font-semibold", style: "color:#3B6D11;") { plain "D = K1 ask − K2 bid" }
      p(id: "bcvs-interval-formula-example", style: "color:#5F5E5A; font-size:12px;")
      div(id: "bcvs-interval-table")
    end
  end

  # bcvs.md §為什麼不直接裸買 LEAPS Call：對照表 + 到期損益交叉價 S*。
  def render_naked_comparison
    render_v3_card(:naked, body_id: "bcvs-naked-body") do
      p(class: "font-mono font-semibold", style: "color:#993C1D;") { plain "S* = K2 + K2 bid" }
      p(style: "color:#5F5E5A; font-size:12px;") { plain "到期價 < S* 時價差策略勝出，> S* 時裸買勝出" }
      div(id: "bcvs-naked-comparison")
    end
  end

  # bcvs.md §提前平倉指引：兩個口徑（毛額現值／淨額獲利）並列，Y=已實現獲利
  # 比例=(現值−成本)÷最大獲利。
  def render_early_close_panel
    render_v3_card(:early_close, body_id: "bcvs-early-close-body") do
      p(class: "font-mono font-semibold", style: "color:#854F0B;") { plain "Y = (現值 − 成本) ÷ 最大獲利" }
      p(style: "color:#5F5E5A; font-size:12px;") { plain "現值以快取 chain 保守估（K1 bid − K2 ask）；Y ≥ 80% 建議考慮獲利了結" }
      div(id: "bcvs-early-close")
    end
  end

  # ---------------------------------------------------------------------------
  # 修復模式（bcvs.md §修復模式，選配輸入）
  # ---------------------------------------------------------------------------
  def render_repair_panel
    details(id: "bcvs-repair-panel", class: "border border-gray-200 rounded-lg") do
      summary(class: "px-4 py-2 text-sm font-medium text-gray-700 cursor-pointer") { plain "修復模式（已持有 K1 長倉，選配）" }
      div(class: "p-4 space-y-3 border-t border-gray-100") do
        p(class: "text-[26px] text-gray-500") { plain "已持有 K1 長倉（如虧損中的 LEAPS）時填入實際進場成本，計算改用此成本取代 K1 ask" }
        div(class: "flex flex-wrap items-center gap-3") do
          label(class: "flex items-center gap-2 text-[24px]") do
            plain "第一腳成本覆寫（basis）"
            input(type: "number", id: "bcvs-repair-basis-input", step: "0.01", min: "0",
                  class: "w-24 border border-gray-300 rounded px-2 py-1 text-right")
          end
          label(class: "flex items-center gap-2 text-[24px]") do
            plain "K1 現價 bid（選配，用於對照平倉）"
            input(type: "number", id: "bcvs-repair-current-bid-input", step: "0.01", min: "0",
                  class: "w-24 border border-gray-300 rounded px-2 py-1 text-right")
          end
        end
        div(id: "bcvs-repair-result", class: "hidden space-y-1 text-[24px]")
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
      div(class: "rounded-xl overflow-hidden border bcvs-notosans", style: "border-color:#97C459;") do
        div(class: "flex items-center gap-2 px-4 py-2.5", style: "background:#3B6D11;") do
          span(class: "text-lg") { plain "✅" }
          span(style: "color:#EAF3DE; font-size:15px; font-weight:500;") { plain "好處" }
        end
        div(class: "p-4", style: "background:#EAF3DE; font-size:14px; color:#2A1A0E;") do
          p do
            plain "成本低於裸買 call、最大損失封頂於淨成本、賣腳權利金部分對沖 theta、修復模式可壓縮虧損 LEAPS 在橫盤～小漲區間的損失。"
          end
        end
      end
      div(class: "rounded-xl overflow-hidden border bcvs-notosans", style: "border-color:#EF9F27;") do
        div(class: "flex items-center gap-2 px-4 py-2.5", style: "background:#854F0B;") do
          span(class: "text-lg") { plain "⚠️" }
          span(style: "color:#FAEEDA; font-size:15px; font-weight:500;") { plain "注意事項" }
        end
        div(class: "p-4 space-y-1", style: "background:#FAEEDA; font-size:14px; color:#2A1A0E;") do
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
    style { raw <<~CSS.html_safe }
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
  def render_hover_style
    style { raw <<~CSS.html_safe }
      #bcvs-chain-table tr:hover {
        background-color: #dbeafe;
      }
      /* bcvs.md §視覺規範 v3「表格」：資料列 hover 淡紫 #EEEDFE，transition 0.12s。 */
      .bcvs-v3-table tbody tr {
        transition: background-color 0.12s ease;
      }
      .bcvs-v3-table tbody tr:hover {
        background-color: #EEEDFE;
      }
      .bcvs-v3-table th {
        border-bottom: 1px solid rgba(0,0,0,0.15);
        text-align: left;
        font-weight: 500;
      }
      .bcvs-v3-table td, .bcvs-v3-table th {
        padding: 4px 8px;
      }
    CSS
  end

  def render_tooltips_script
    script { raw tooltips_script_js.html_safe }
  end

  def tooltips_script_js
    <<~JS
      (function () {
        var BCVS_COL_EXPLAIN = #{bcvs_col_explain_json};
        var BCVS_TOUR_STEPS = #{bcvs_tour_steps_json};

        var tip = document.createElement('div');
        tip.id = 'bcvs-col-tip';
        tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
        document.body.appendChild(tip);
        var tT = tip.querySelector('.tip-t'), tB = tip.querySelector('.tip-b');
        function posTip(e) {
          var x = e.clientX + 14, y = e.clientY + 12,
              w = tip.offsetWidth || 280, h = tip.offsetHeight || 100;
          if (x + w > window.innerWidth - 10)  x = e.clientX - w - 10;
          if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
          tip.style.left = x + 'px'; tip.style.top = y + 'px';
        }
        document.addEventListener('mouseover', function (e) {
          var el = e.target.closest('[data-tip-key]');
          if (el) {
            var d = BCVS_COL_EXPLAIN[el.dataset.tipKey];
            if (!d) return;
            tT.textContent = d.title; tB.textContent = d.desc;
            tip.style.opacity = '1'; posTip(e);
          } else { tip.style.opacity = '0'; }
        });
        document.addEventListener('mousemove', function (e) {
          if (tip.style.opacity !== '0') posTip(e);
        });
        document.addEventListener('mouseout', function (e) {
          if (!e.target.closest('[data-tip-key]')) tip.style.opacity = '0';
        });

        function drv() { return window.driver && window.driver.js && window.driver.js.driver; }
        document.addEventListener('click', function (e) {
          var el = e.target.closest('[data-tip-key]');
          if (el && drv()) {
            var d = BCVS_COL_EXPLAIN[el.dataset.tipKey];
            if (!d) return;
            tip.style.opacity = '0';
            drv()({ animate: true, allowClose: true, overlayOpacity: 0.35,
                    steps: [{ element: el, popover: { title: d.title, description: d.desc, side: 'bottom', align: 'center' } }] }).drive();
            return;
          }

          // bcvs.md §導覽與欄位說明規範 B：9 步全頁導覽——步驟數固定 9，
          // 頁面當下不存在的元素直接 filter 掉（不強制報錯），任何階段都能點。
          var tourBtn = e.target.closest('#bcvs-tour-btn');
          if (tourBtn && drv()) {
            var steps = BCVS_TOUR_STEPS
              .filter(function (s) { return document.querySelector(s.el); })
              .map(function (s) {
                return { element: s.el, popover: { title: s.title, description: s.desc, side: 'bottom', align: 'center' } };
              });
            if (steps.length) {
              drv()({ animate: true, allowClose: true, overlayOpacity: 0.4, showProgress: true, steps: steps }).drive();
            }
          }
        });
      })();
    JS
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
    script { raw script_js.html_safe }
  end

  def script_js
    <<~JS
      (function () {
        function csrf() {
          var m = document.querySelector('meta[name="csrf-token"]');
          return m ? m.content : '';
        }

        function fmt(n) { return (typeof n === 'number' && !isNaN(n) && n !== null) ? n.toFixed(2) : '—'; }

        // 與 Ruby #strike_row_id 用同一種格式化方式組 row id，避免 Float#to_s
        // 與 JS Number 序列化不一致造成兩端 id 對不上。
        function strikeRowId(strike) {
          return 'bcvs-row-' + Number(strike).toFixed(2).replace('.', '_');
        }

        var CURRENT_PRICE = #{@underlying_price.to_json};

        function pollJob(jobId, statusPath, onDone) {
          var attempts = 0;
          var timer = setInterval(function () {
            if (++attempts > 60) { clearInterval(timer); onDone('error'); return; }
            fetch(statusPath + '?job_id=' + jobId)
              .then(function (r) { return r.json(); })
              .then(function (d) {
                if (d.status === 'pending' || d.status === 'not_found') return;
                clearInterval(timer);
                onDone(d.status);
              }).catch(function () {});
          }, 2000);
        }

        function showProgress() {
          var bar = document.getElementById('bcvs-progress');
          if (bar) bar.classList.remove('hidden');
        }

        // ── Step1: 送出代號 → 抓到期日 ──────────────────────────────────────
        var form = document.getElementById('bcvs-symbol-form');
        var inp  = document.getElementById('bcvs-symbol-input');
        if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });

        function fetchExpirations(symbol) {
          var loading = document.getElementById('bcvs-loading');
          if (loading) loading.classList.remove('hidden');
          showProgress();
          var submitBtn = document.getElementById('bcvs-submit-btn');
          var retryBtnEl = document.getElementById('bcvs-fetch-expirations-btn');
          if (submitBtn) submitBtn.disabled = true;
          if (retryBtnEl) retryBtnEl.disabled = true;
          fetch('#{bull_call_spreads_fetch_expirations_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({ symbol: symbol })
          })
          .then(function (r) { return r.json(); })
          .then(function (d) {
            if (d.status === 'ready') {
              window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol;
            } else if (d.status === 'cdp_offline') {
              window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol + '&job_status=cdp_offline';
            } else if (d.job_id) {
              pollJob(d.job_id, '#{bull_call_spreads_status_path}', function (status) {
                window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol + '&job_status=' + status;
              });
            } else {
              window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol + '&job_status=error';
            }
          }).catch(function () {
            window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol + '&job_status=error';
          });
        }

        if (form) {
          form.addEventListener('submit', function (e) {
            e.preventDefault();
            var symbol = inp ? inp.value.trim().toUpperCase() : '';
            if (!symbol) return;
            fetchExpirations(symbol);
          });
        }

        var retryBtn = document.getElementById('bcvs-fetch-expirations-btn');
        if (retryBtn) {
          retryBtn.addEventListener('click', function () {
            fetchExpirations(#{@symbol.to_json});
          });
        }

        // ── Step2: 點到期日 → 抓 Call 鏈 ─────────────────────────────────────
        document.querySelectorAll('[data-bcvs-expiration-btn]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            var exp = btn.getAttribute('data-exp');
            var symbol = #{@symbol.to_json};
            showProgress();
            document.querySelectorAll('[data-bcvs-expiration-btn]').forEach(function (b) { b.disabled = true; });
            fetch('#{bull_call_spreads_fetch_chain_path}', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
              body: JSON.stringify({ symbol: symbol, expiration: exp })
            })
            .then(function (r) { return r.json(); })
            .then(function (d) {
              var base = '#{bull_call_spreads_path}?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp);
              if (d.status === 'ready') {
                window.location.href = base;
              } else if (d.status === 'cdp_offline') {
                window.location.href = base + '&chain_job_status=cdp_offline';
              } else if (d.job_id) {
                pollJob(d.job_id, '#{bull_call_spreads_status_path}', function (status) { window.location.href = base + '&chain_job_status=' + status; });
              } else {
                window.location.href = base + '&chain_job_status=error';
              }
            }).catch(function () {
              window.location.href = '#{bull_call_spreads_path}?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp) + '&chain_job_status=error';
            });
          });
        });

        // ── Step3/4: K1 下拉 → 三 tab K2 建議 ────────────────────────────────
        var lastTabs = null;
        var activeTab = 'balanced';

        function currentLots() {
          var el = document.getElementById('bcvs-lots-input');
          var n = el ? parseInt(el.value, 10) : 1;
          return (!n || n < 1) ? 1 : n;
        }

        function fmtLots(perLot, lots) {
          if (typeof perLot !== 'number' || isNaN(perLot) || perLot === null) return '—';
          if (lots <= 1) return '$' + fmt(perLot);
          return '$' + fmt(perLot) + ' × ' + lots + ' = $' + fmt(perLot * lots);
        }

        function setActiveTab(kind) {
          activeTab = kind;
          document.querySelectorAll('[data-bcvs-recommend-tab]').forEach(function (btn) {
            var active = btn.getAttribute('data-bcvs-recommend-tab') === kind;
            btn.classList.toggle('bg-blue-600', active);
            btn.classList.toggle('text-white', active);
            btn.classList.toggle('border-blue-600', active);
            btn.classList.toggle('bg-white', !active);
            btn.classList.toggle('text-gray-700', !active);
            btn.classList.toggle('border-gray-300', !active);
          });
          renderTab();
        }

        function highlightK1K2(k1, k2) {
          document.querySelectorAll('#bcvs-chain-table tr').forEach(function (r) {
            r.classList.remove('!bg-blue-50', '!bg-red-50');
          });
          var k1Row = document.getElementById(strikeRowId(k1));
          var k2Row = document.getElementById(strikeRowId(k2));
          if (k1Row) k1Row.classList.add('!bg-blue-50');
          if (k2Row) k2Row.classList.add('!bg-red-50');
        }

        function renderTab() {
          var grid = document.getElementById('bcvs-calc-grid');
          var warn = document.getElementById('bcvs-calc-warning');
          var errEl = document.getElementById('bcvs-recommend-error');
          if (!grid || !lastTabs) return;

          var tab = lastTabs[activeTab];
          if (!tab) {
            grid.innerHTML = '';
            if (errEl) { errEl.classList.remove('hidden'); errEl.textContent = '此分頁找不到合適的 K2 候選（可能候選 strike 不足）。'; }
            return;
          }
          if (errEl) errEl.classList.add('hidden');

          highlightK1K2(tab.k2 === undefined ? null : document.getElementById('bcvs-k1-select').value, tab.k2);

          if (tab.warning === 'invalid_width') {
            warn.textContent = '⚠️ K2 必須高於 K1';
            warn.classList.remove('hidden');
          } else if (tab.warning === 'non_debit') {
            warn.textContent = '⚠️ 此組合淨成本非正值，報價可能異常';
            warn.classList.remove('hidden');
          } else {
            warn.classList.add('hidden');
          }

          var lots = currentLots();
          // bcvs.md §策略定義／§功能流程 步驟3：淨成本 debit（每股，另示 mid
          // 供參）與每口成本（×100×口數）是規格明列的兩個獨立欄位，不可合併
          // 只顯示其中一個。
          var debitMidHtml = (typeof tab.debit_mid === 'number') ? '（mid 版 $' + fmt(tab.debit_mid) + ' 供參）' : '';
          grid.innerHTML =
            '<div><dt class="text-[24px] text-gray-500">K2</dt><dd class="font-semibold">$' + fmt(tab.k2) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">淨成本 debit</dt><dd class="font-semibold">$' + fmt(tab.debit) + debitMidHtml + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">每口成本</dt><dd class="font-semibold">' + fmtLots(tab.cost_per_contract, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">' + fmtLots(tab.max_profit, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">最大損失</dt><dd class="font-semibold text-red-700">' + fmtLots(tab.max_loss, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">損益兩平</dt><dd class="font-semibold">$' + fmt(tab.breakeven) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">報酬風險比</dt><dd class="font-semibold text-yellow-700">' + (tab.risk_reward === null ? '—' : tab.risk_reward) + '</dd></div>';

          renderIntervalTable(tab, lots);
          renderNakedComparison(tab, lots);
          renderEarlyClose(tab, lots);
          fillRepairFromTab(tab);
        }

        // ── 損益區間表（bcvs.md §損益區間表：動態，以實際數字渲染）───────────────
        // bcvs.md §視覺規範：損益區間表列色 — 虧損列紅字、損平列灰字、獲利列綠字。
        function renderIntervalTable(tab, lots) {
          var el = document.getElementById('bcvs-interval-table');
          var exampleEl = document.getElementById('bcvs-interval-formula-example');
          if (!el || tab.warning === 'invalid_width') {
            if (el) el.innerHTML = '';
            if (exampleEl) exampleEl.textContent = '';
            return;
          }

          if (exampleEl) exampleEl.textContent = '本次範例：D = $' + fmt(tab.debit) + '（K1 $' + fmt(tab.k1) + ' → K2 $' + fmt(tab.k2) + '）';

          var k1 = tab.k1, k2 = tab.k2, be = tab.breakeven;
          var maxLoss = tab.max_loss, maxProfit = tab.max_profit;
          var price = CURRENT_PRICE;
          var exampleHtml = '';

          if (typeof price === 'number' && price > k1 && price < be) {
            var pnl = (price - k1 - tab.debit) * 100 * lots;
            exampleHtml = '（如以現價 $' + fmt(price) + ' 到期 → ' + (pnl >= 0 ? '+' : '') + '$' + fmt(pnl) + '）';
          }
          var exampleHtml2 = '';
          if (typeof price === 'number' && price >= be && price < k2) {
            var pnl2 = (price - k1 - tab.debit) * 100 * lots;
            exampleHtml2 = '（如以現價 $' + fmt(price) + ' 到期 → +$' + fmt(pnl2) + '）';
          }

          // bcvs.md §視覺規範 v3：損益區間表列色——虧損 #A32D2D、損平 #5F5E5A、
          // 獲利 #3B6D11，三欄（到期股價區間／結果／金額每口）。
          var rows = [
            { color: '#A32D2D', range: '≤ $' + fmt(k1), result: '賠掉全部成本', amount: '−' + fmtLots(maxLoss, lots) },
            { color: '#A32D2D', range: '$' + fmt(k1) + ' ~ $' + fmt(be), result: '部分虧損，隨股價遞減 ' + exampleHtml, amount: '' },
            { color: '#5F5E5A', range: '= $' + fmt(be), result: '損益兩平', amount: '$0' },
            { color: '#3B6D11', range: '$' + fmt(be) + ' ~ $' + fmt(k2), result: '開始獲利，隨股價遞增 ' + exampleHtml2, amount: '' },
            { color: '#3B6D11', range: '≥ $' + fmt(k2), result: '最大獲利（封頂）', amount: '+' + fmtLots(maxProfit, lots) }
          ];
          el.innerHTML =
            '<table class="bcvs-v3-table w-full"><thead><tr>' +
            '<th>到期股價區間</th><th>結果</th><th class="text-right">金額（每口）</th>' +
            '</tr></thead><tbody>' +
            rows.map(function (r) {
              return '<tr style="color:' + r.color + '"><td>' + r.range + '</td><td>' + r.result + '</td><td class="text-right">' + r.amount + '</td></tr>';
            }).join('') +
            '</tbody></table>';
        }

        // ── 裸買 LEAPS 對照表（bcvs.md §為什麼不直接裸買）─────────────────────
        function renderNakedComparison(tab, lots) {
          var el = document.getElementById('bcvs-naked-comparison');
          if (!el || tab.warning === 'invalid_width') { if (el) el.innerHTML = ''; return; }

          var priceNote = '';
          if (typeof CURRENT_PRICE === 'number' && typeof tab.s_star === 'number') {
            priceNote = CURRENT_PRICE < tab.s_star
              ? '目前現價 $' + fmt(CURRENT_PRICE) + ' 低於 S*，價差策略暫時領先。'
              : '目前現價 $' + fmt(CURRENT_PRICE) + ' 高於 S*，裸買暫時領先。';
          }

          el.innerHTML =
            '<table class="bcvs-v3-table w-full"><thead><tr>' +
            '<th>項目</th><th class="text-right">裸買 K1 Call</th><th class="text-right">價差（K1/K2）</th></tr></thead><tbody>' +
            '<tr><td>每口成本</td><td class="text-right">' + fmtLots(tab.naked_cost, lots) + '</td><td class="text-right">' + fmtLots(tab.cost_per_contract, lots) + '</td></tr>' +
            '<tr><td>最大損失</td><td class="text-right" style="color:#A32D2D">' + fmtLots(tab.naked_cost, lots) + '</td><td class="text-right" style="color:#3B6D11">' + fmtLots(tab.max_loss, lots) + '（金額小得多）</td></tr>' +
            '<tr><td>損益兩平</td><td class="text-right">$' + fmt(tab.naked_breakeven) + '</td><td class="text-right" style="color:#3B6D11">$' + fmt(tab.breakeven) + '（低得多）</td></tr>' +
            '<tr><td>最大獲利</td><td class="text-right" style="color:#3B6D11">無上限</td><td class="text-right">' + fmtLots(tab.max_profit, lots) + '（封頂）</td></tr>' +
            '</tbody></table>' +
            '<p class="mt-2" style="color:#5F5E5A; font-size:12px;">本次範例：S* = $' + fmt(tab.k2) + ' + $' + fmt(tab.s_star - tab.k2) + ' = $' + fmt(tab.s_star) + '</p>' +
            '<p class="mt-1">' + priceNote + '</p>';
        }

        // ── 提前平倉指引（bcvs.md §提前平倉指引）───────────────────────────────
        // bcvs.md §提前平倉指引：兩個口徑（毛額現值／淨額獲利）並列，嚴禁混用；
        // 上限也成對呈現（收回上限=(K2−K1)×100，獲利上限=收回上限−成本）。
        function renderEarlyClose(tab, lots) {
          var el = document.getElementById('bcvs-early-close');
          if (!el || tab.warning === 'invalid_width') { if (el) el.innerHTML = ''; return; }

          if (tab.closeout_value === null || tab.closeout_value === undefined) {
            el.innerHTML = '<p style="color:#5F5E5A">需要 K1 現價 bid 才能估算平倉可收回金額。</p>';
            return;
          }

          var pct = tab.realized_pct;
          var suggestHtml = (typeof pct === 'number' && pct >= 80)
            ? '<p class="font-semibold mt-2" style="color:#3B6D11">✅ 已實現 ' + pct + '%，達 80% 閾值，建議考慮獲利了結——剩餘部分要再抱數月，報酬/時間比會急遽變差，還多扛提前指派與回檔風險。</p>'
            : '';

          el.innerHTML =
            '<p>現在平倉可收回（毛額） <strong>' + fmtLots(tab.closeout_value, lots) + '</strong>（收回上限 ' + fmtLots(tab.spread_max_value, lots) + '）</p>' +
            '<p>等於獲利（淨額，收回−成本） <strong style="color:' + (tab.closeout_profit >= 0 ? '#3B6D11' : '#A32D2D') + '">' + fmtLots(tab.closeout_profit, lots) + '</strong>（獲利上限 ' + fmtLots(tab.max_profit, lots) + '）</p>' +
            '<p>已實現獲利比例 Y = <strong>' + (typeof pct === 'number' ? pct + '%' : '—') + '</strong></p>' +
            '<p class="mt-1" style="color:#5F5E5A; font-size:12px;">本次範例：Y = ($' + fmt(tab.closeout_value) + ' − $' + fmt(tab.cost_per_contract) + ') ÷ $' + fmt(tab.max_profit) + ' = ' + (typeof pct === 'number' ? pct + '%' : '—') + '</p>' +
            suggestHtml +
            '<p class="mt-2" style="color:#5F5E5A">平倉一律組合單兩腳同出。</p>';
        }

        document.querySelectorAll('[data-bcvs-recommend-tab]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            setActiveTab(btn.getAttribute('data-bcvs-recommend-tab'));
          });
        });

        var lotsInput = document.getElementById('bcvs-lots-input');
        if (lotsInput) lotsInput.addEventListener('input', renderTab);

        function runRecommend(k1, k1Ask, k1Bid) {
          var payload = { symbol: #{@symbol.to_json}, expiration: #{@expiration.to_json}, k1: k1, k1_ask: k1Ask };
          if (!isNaN(k1Bid)) payload.k1_bid = k1Bid;
          fetch('#{bull_call_spreads_recommend_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify(payload)
          })
          .then(function (r) { return r.json(); })
          .then(function (d) {
            var tabsEl = document.getElementById('bcvs-recommend-tabs');
            if (d.error) {
              if (tabsEl) tabsEl.classList.add('hidden');
              return;
            }
            lastTabs = d.tabs;
            if (tabsEl) tabsEl.classList.remove('hidden');
            setActiveTab('balanced');
          }).catch(function () {});
        }

        var k1Select = document.getElementById('bcvs-k1-select');
        if (k1Select) {
          k1Select.addEventListener('change', function () {
            var opt = k1Select.options[k1Select.selectedIndex];
            if (!opt || !opt.value) return;
            runRecommend(parseFloat(opt.value), parseFloat(opt.getAttribute('data-ask')), parseFloat(opt.getAttribute('data-bid')));
          });
          if (k1Select.value) k1Select.dispatchEvent(new Event('change'));
        }

        // ── 修復模式 ─────────────────────────────────────────────────────────
        function fillRepairFromTab(tab) {
          // basis 欄位保留使用者已輸入的值，不覆蓋；K2/K2_bid 隨目前 tab 更新。
          var basisInput = document.getElementById('bcvs-repair-basis-input');
          if (basisInput) basisInput.dataset.k2 = tab.k2;
          if (basisInput) basisInput.dataset.k2Bid = (tab.debit !== null && tab.max_loss !== null) ? '' : '';
          runRepairIfReady();
        }

        function runRepairIfReady() {
          var basisInput = document.getElementById('bcvs-repair-basis-input');
          var currentBidInput = document.getElementById('bcvs-repair-current-bid-input');
          var resultEl = document.getElementById('bcvs-repair-result');
          if (!basisInput || !resultEl || !lastTabs) return;
          var basis = parseFloat(basisInput.value);
          if (isNaN(basis)) { resultEl.classList.add('hidden'); return; }

          var tab = lastTabs[activeTab];
          if (!tab || tab.k2 === undefined) return;
          var k1 = parseFloat(document.getElementById('bcvs-k1-select').value);
          var k2Bid = tab.k2 - tab.breakeven + k1; // k2_bid = breakeven - k1... reconstruct if needed
          // k2_bid is directly derivable from tab.debit and the select's ask, but
          // simplest reliable source is the chain row rendered for this K2.
          var k2Row = document.getElementById(strikeRowId(tab.k2));
          var bidAttr = k2Row ? k2Row.getAttribute('data-bid') : null;
          if (bidAttr === null || bidAttr === '') return;
          k2Bid = parseFloat(bidAttr);

          var payload = { k1: k1, k2: tab.k2, k2_bid: k2Bid, basis: basis };
          var currentBid = parseFloat(currentBidInput ? currentBidInput.value : '');
          if (!isNaN(currentBid)) payload.k1_current_bid = currentBid;
          if (typeof CURRENT_PRICE === 'number') payload.current_price = CURRENT_PRICE;

          fetch('#{bull_call_spreads_calculate_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify(payload)
          })
          .then(function (r) { return r.json(); })
          .then(renderRepairResult)
          .catch(function () {});
        }

        // bcvs.md §修復模式：三種到期情境（≤K1／中間／≥K2）與「對照現在直接
        // 平倉」並列顯示——中間情境是連續函數，只在現價落在 K1~K2 之間時
        // 後端才會回傳數字（否則為 null，不外推造值）。
        function renderRepairResult(d) {
          var resultEl = document.getElementById('bcvs-repair-result');
          if (!resultEl) return;
          resultEl.classList.remove('hidden');

          var warningHtml = '';
          if (d.warning === 'locked_loss') {
            warningHtml = '<p class="text-red-700 font-semibold">⚠️ 此組合鎖定虧損 $' + fmt(Math.abs(d.locked_result_total)) + '／口（basis 需 ≤ $' + fmt(d.breakeven_basis) + ' 才不虧損）</p>';
          }

          var midHtml = (d.mid_pnl_total !== null && d.mid_pnl_total !== undefined)
            ? '<p>中間情境（現價 $' + fmt(CURRENT_PRICE) + '）：$' + fmt(d.mid_pnl_total) + '／口</p>'
            : '';

          var closeoutHtml = '';
          if (d.closeout_pnl !== null && d.closeout_pnl !== undefined) {
            closeoutHtml = '<p>對照現在直接平倉：收回 $' + fmt(d.closeout_proceeds) + '（損益 $' + fmt(d.closeout_pnl) + '）</p>';
          }

          resultEl.innerHTML =
            warningHtml +
            '<p>≤K1 情境：$' + fmt(d.below_k1_pnl_total) + '／口</p>' +
            midHtml +
            '<p>≥K2 鎖定結果：$' + fmt(d.locked_result_total) + '／口（分水嶺 basis = $' + fmt(d.breakeven_basis) + '）</p>' +
            closeoutHtml;
        }

        [ 'bcvs-repair-basis-input', 'bcvs-repair-current-bid-input' ].forEach(function (id) {
          var el = document.getElementById(id);
          if (el) el.addEventListener('input', runRepairIfReady);
        });
      })();
    JS
  end
end
