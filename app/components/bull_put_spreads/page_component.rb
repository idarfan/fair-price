# frozen_string_literal: true

module BullPutSpreads
end

# BPUS §4：單頁步驟式 UI。Step1 代號 → Step2 履約日 → Step3/4 從同一張 Put
# strike 表格依序點選保護腳（藍）/ CSP 腳（紅）→ Step5 即時計算。抓取（履約日、
# Put 鏈）都要打 CDP，走 job+輪詢+整頁重載（沿用 TechnicalDashboard 的
# mp_filter_js 模式）；計算不碰 CDP，走同步 fetch，不整頁重載。
class BullPutSpreads::PageComponent < ApplicationComponent
  def initialize(symbol: nil, symbol_error: nil, scrape_status: nil, expirations: nil,
                 underlying_price: nil, expiration: nil, chain_status: nil, put_chain: nil)
    @symbol           = symbol
    @symbol_error     = symbol_error
    @scrape_status    = scrape_status
    @expirations      = Array(expirations)
    @underlying_price = underlying_price
    @expiration       = expiration
    @chain_status     = chain_status
    @put_chain        = Array(put_chain).sort_by { |r| r["strike"].to_f }
  end

  def view_template
    div(class: "space-y-6") do
      render_header
      render_symbol_form
      render_progress_bar
      render_symbol_error if @symbol_error
      render_expiration_section if @symbol
      render_chain_section if @expiration && @chain_status
      render_notes
    end
    render_hover_style
    render_tooltips_script
    render_script
  end

  private

  # ---------------------------------------------------------------------------
  # Header / Step1
  # ---------------------------------------------------------------------------
  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") { plain "牛市差價看跌期權(三級版)" }
      p(class: "text-[26px] text-gray-500 mt-0.5") do
        plain "三級帳戶 Bull Put Spread 試算 · 複式單押金 = (價差寬度 × 100) − 淨權利金"
      end
    end
  end

  def render_symbol_form
    form(id: "bpus-symbol-form", action: bull_put_spreads_path, method: "get",
         class: "flex items-center gap-2") do
      input(type: "text", id: "bpus-symbol-input", name: "symbol",
            value: @symbol.to_s, placeholder: "股票代號，例如 RKLB",
            maxlength: 6, autocomplete: "off",
            class: "px-3 py-2 border border-gray-300 rounded-lg text-sm w-48 uppercase")
      button(type: "submit", id: "bpus-submit-btn",
             class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700") do
        plain "查詢履約日"
      end
      span(id: "bpus-loading", class: "hidden text-xs text-blue-600 animate-pulse") { plain "抓取中…" }
    end
  end

  # 進度條：抓履約日／Put 鏈共用同一條，JS 依情境顯示/隱藏、並在抓取期間
  # disable 對應按鈕（避免使用者重複送出或在抓取途中切換履約日）。
  def render_progress_bar
    div(id: "bpus-progress", class: "hidden h-1.5 w-full bg-gray-100 rounded-full overflow-hidden") do
      div(id: "bpus-progress-fill", class: "h-full w-1/3 bg-blue-500 rounded-full bpus-progress-anim")
    end
  end

  def render_symbol_error
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg") do
      plain "⚠️ #{@symbol_error}"
    end
  end

  # ---------------------------------------------------------------------------
  # Step2：履約日
  # ---------------------------------------------------------------------------
  def render_expiration_section
    div(class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 2 · 選擇履約日" }

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
            button(type: "button", class: btn_class, data: { exp: exp[:value], "bpus-expiration-btn": "" }) do
              plain exp[:label]
            end
          end
        end
      when :ready_to_fetch
        p(class: "text-sm text-gray-500") { plain "尚未抓取，請按下方按鈕從 Barchart 讀取履約日清單" }
        button(type: "button", id: "bpus-fetch-expirations-btn",
               class: "px-3 py-1.5 bg-blue-600 text-white text-xs font-medium rounded-lg hover:bg-blue-700") do
          plain "抓取履約日"
        end
      when :session_expired
        render_status_alert("Barchart 登入已過期，請重新登入後重試")
      when :cdp_offline
        render_status_alert("CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動")
      when :no_candidates
        render_status_alert("找不到履約日，請確認代號是否有期權交易")
      else
        render_status_alert("抓取失敗，請稍後重試")
      end
    end
  end

  def render_status_alert(msg)
    div(class: "px-4 py-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg") { plain "⚠️ #{msg}" }
  end

  # ---------------------------------------------------------------------------
  # Step3/4：Put 鏈表格 + Step5：計算結果
  # ---------------------------------------------------------------------------
  def render_chain_section
    div(class: "space-y-4") do
      case @chain_status
      when :cached
        render_chain_table
      when :session_expired
        render_status_alert("Barchart 登入已過期，請重新登入後重試")
      when :cdp_offline
        render_status_alert("CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動")
      when :no_candidates
        render_status_alert("此履約日無可用的 Put 報價")
      when :ready_to_fetch
        p(class: "text-sm text-gray-500") { plain "正在抓取 #{@expiration} 的 Put 鏈…" }
      else
        render_status_alert("抓取失敗，請稍後重試")
      end
    end
  end

  # 欄位順序跟 Barchart Puts 表格一致：Strike/Moneyness/Bid/Mid/Ask/Last/Change/
  # %Change/Volume/OI/OI Chg/IV/Delta——選腳表格(render_selected_legs_panel)
  # 沿用同一份 COLUMNS 定義，兩處欄位保證不會各自漂移。
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

  # 表頭 driver.js 教學 tooltip（hover 顯示 + 點擊彈出 popover），沿用
  # LEAPS/PMCC 表格既有的 data-tip-key 委派機制與 #leaps-col-tip 樣式
  # （app/assets/tailwind/application.css 已是全站共用 CSS，不用重刻一份）。
  COLUMN_EXPLAIN = {
    "strike" => {
      title: "履約價（Strike）",
      desc: "選擇權合約約定的履約價格。保護腳(Long Put)取 Ask 買入、CSP 腳(Short Put)取 Bid 賣出，兩腳履約價之差即為價差寬度。"
    },
    "moneyness" => {
      title: "Moneyness（價內外程度）",
      desc: "(現價−履約價)/現價 的百分比。負值代表 Put 為價外(OTM)，正值代表價內(ITM)——數字越負代表這個履約價離現價越遠、越安全但權利金越低。"
    },
    "bid" => {
      title: "Bid（買方出價）",
      desc: "市場上買方目前願意支付的最高價格。CSP 腳(Short Put)以 Bid 掛單可立即成交，但只拿得到最低價，本頁「賣方取 bid」就是採用這個保守估算。"
    },
    "mid" => {
      title: "Mid（中價）",
      desc: "(Bid+Ask)/2，市場中間價。實際下單建議掛 Mid 價、耐心等候造市商撮合成交，通常能拿到比保守估算更好的價格。"
    },
    "ask" => {
      title: "Ask（賣方要價）",
      desc: "市場上賣方目前願意賣出的最低價格。保護腳(Long Put)以 Ask 掛單可立即成交，但要付最高價，本頁「買方取 ask」就是採用這個保守估算。"
    },
    "last" => {
      title: "Last（最後成交價）",
      desc: "這個履約價最近一次實際成交的價格，可能是幾分鐘前、也可能是好幾天前——成交量少的履約價，這個數字參考價值較低。"
    },
    "change" => {
      title: "Change（漲跌）",
      desc: "這個履約價的權利金比前一交易日收盤價變動了多少（絕對金額）。顯示 unch 代表今天完全沒有成交，無從比較。"
    },
    "pct_change" => {
      title: "%Change（漲跌幅）",
      desc: "權利金變動的百分比。選擇權基期價格通常很小，同樣的漲跌金額換算成百分比可能非常誇張，建議搭配 Change 絕對金額一起看。"
    },
    "volume" => {
      title: "Volume（成交量）",
      desc: "當日這個履約價實際成交的口數。量越大代表流動性越好，成交價越貼近真實市場共識；量是 0 代表今天還沒有人成交。"
    },
    "open_interest" => {
      title: "OI（未平倉量）",
      desc: "目前市場上尚未平倉的合約總口數，反映這個履約價有多少人持有部位。OI 過低代表流動性差，實際成交價可能明顯偏離畫面估算，注意事項§4 提過的風險就是這個。"
    },
    "oi_change" => {
      title: "OI Chg（未平倉量變化）",
      desc: "跟前一交易日相比，未平倉量增加或減少了多少。大幅增加通常代表當天有新倉位進場（開倉），減少則可能是平倉。"
    },
    "iv" => {
      title: "IV（隱含波動率）",
      desc: "市場對這個履約價未來波動幅度的預期，數字越高代表市場預期波動越劇烈、權利金越貴。財報前 IV 通常會墊高，財報後容易 IV crush（注意事項§3）。"
    },
    "delta" => {
      title: "Delta（避險比率）",
      desc: "股價變動 $1 時，這個 Put 權利金理論上變動多少，也常被當作「到期價內機率」的粗略估計。CSP 腳建議分頁就是用 |Delta| 挑選履約價——數字越大代表離價平越近、被指派機率越高。"
    }
  }.freeze

  def render_chain_table
    div(class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 3/4 · 先選保護腳(藍)，再選 CSP 腳(紅)" }
      p(class: "text-[26px] text-gray-500") do
        plain "保守計價：賣方取 bid、買方取 ask，以最不利成交價估算，實際可用 mid 價掛單"
      end
      # 選腳結果放表格「上方」——選完不用捲動到下面才看得到。
      render_selected_legs_panel
      p(class: "text-xs") do
        a(href: "#", id: "bpus-reset-legs", class: "text-blue-600 hover:underline") { plain "清空已選腳" }
      end
      render_recommend_tabs
      render_calc_panel
      div(class: "w-full overflow-x-auto border border-gray-200 rounded-lg") do
        table(id: "bpus-chain-table", class: "min-w-full text-xs whitespace-nowrap bpus-phase-protection") do
          thead(class: "bg-gray-50 text-gray-500 uppercase") do
            tr do
              COLUMNS.each do |col|
                th(id: "bpus-th-#{col[:key]}", data_tip_key: col[:key],
                   class: "px-2 py-1.5 #{col[:align]}") { plain col[:label] }
              end
            end
          end
          tbody do
            @put_chain.each_with_index { |row, i| render_chain_row(row, i) }
          end
        end
      end
    end
  end

  # 保守/激進收租建議分頁：純前端 JS 從已渲染的表格 data-* 屬性挑選建議兩腳
  # （不需要額外的 Ruby/JSON round trip，資料本來就已經在 DOM 裡）。不點擊時
  # 說明區塊維持 hidden，不佔版面。
  def render_recommend_tabs
    div(class: "flex items-center gap-2 mt-2") do
      button(type: "button", class: "px-3 py-1.5 rounded-lg text-[24px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
             data: { "bpus-recommend-tab": "conservative" }) { plain "保守收租" }
      button(type: "button", class: "px-3 py-1.5 rounded-lg text-[24px] font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
             data: { "bpus-recommend-tab": "aggressive" }) { plain "激進收租" }
    end
    div(id: "bpus-recommend-explain", class: "hidden mt-2 px-3 py-2 bg-yellow-50 border border-yellow-200 text-yellow-900 text-[24px] rounded-lg")
    div(id: "bpus-volatility-explain", class: "hidden mt-2 px-3 py-2 bg-indigo-50 border border-indigo-200 text-indigo-900 text-[24px] rounded-lg")
  end

  def render_chain_row(row, index)
    strike = row["strike"].to_f
    bid    = row["bid"]
    ask    = row["ask"]
    no_quote = bid.nil? && ask.nil?

    row_class = (index.odd? ? "bg-gray-50/50" : "") + " border-t border-gray-100"
    row_class += " opacity-40 pointer-events-none" if no_quote

    data_attrs = { "bpus-row": "" }
    COLUMNS.each { |col| data_attrs[col[:key].to_sym] = row[col[:key]] }
    data_attrs[:strike] = strike

    tr(class: row_class, data: data_attrs) do
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

  # Change/%Change/OI Chg 欄位沿用 Barchart 自己的顯示慣例：完全沒變動(0)顯示
  # 「unch」灰字，不是「+0.00」——0 在 Ruby 是 truthy，用 row["x"] ? ... 判斷會
  # 誤把 0 當成「有變動」，這裡用明確的 nil?/zero? 分開三種狀態。
  def render_delta_cell(value)
    if value.nil?
      td(class: "px-4 py-2 text-right text-gray-400") { plain "—" }
    elsif value.to_f.zero?
      td(class: "px-4 py-2 text-right text-gray-400") { plain "unch" }
    else
      td(class: "px-4 py-2 text-right #{change_color(value)}") { plain yield(value.to_f) }
    end
  end

  # 選好保護腳後立即完整呈現該列讀到的 Barchart 原始資料(不用等 CSP 腳也選完)，
  # 放在表格「上方」不用捲動；選好 CSP 腳後再多長一排——兩排跟主表格同一套
  # COLUMNS 定義，不另造第二套欄位格式。
  def render_selected_legs_panel
    div(id: "bpus-selected-legs", class: "hidden mb-3 w-full overflow-x-auto border border-gray-200 rounded-lg") do
      table(class: "min-w-full text-xs whitespace-nowrap") do
        thead(class: "bg-gray-50 text-gray-500 uppercase") do
          tr do
            th(class: "px-2 py-1.5 text-left") { plain "腳位" }
            th(class: "px-2 py-1.5 text-left") { plain "方式" }
            COLUMNS.each { |col| th(class: "px-2 py-1.5 #{col[:align]}") { plain col[:label] } }
          end
        end
        tbody do
          render_selected_leg_row(id: "bpus-protection-row", label: "保護腳(Long Put)", action: "Buy to Open", row_class: "bg-blue-50 text-blue-900")
          render_selected_leg_row(id: "bpus-csp-row", label: "CSP腳(Short Put)", action: "Sell to Open", row_class: "bg-red-50 text-red-900")
        end
      end
    end
  end

  def render_selected_leg_row(id:, label:, action:, row_class:)
    tr(id: id, class: "hidden border-t border-gray-100 #{row_class}") do
      td(class: "px-2 py-1.5 font-medium") { plain label }
      td(class: "px-2 py-1.5 font-medium") { plain action }
      COLUMNS.each { |col| td(class: "px-2 py-1.5 text-right", data: { field: col[:key] }) }
    end
  end

  def render_calc_panel
    div(id: "bpus-calc-panel", class: "hidden space-y-3 p-4 bg-white border border-gray-200 rounded-lg") do
      div(class: "flex items-center justify-between") do
        h2(class: "text-sm font-semibold text-gray-700") { plain "Step 5 · 計算結果" }
        label(class: "flex items-center gap-2 text-[24px] text-gray-600") do
          plain "口數"
          input(type: "number", id: "bpus-lots-input", value: "1", min: "1", step: "1",
                class: "w-16 border border-gray-300 rounded px-2 py-1 text-right")
        end
      end
      div(id: "bpus-calc-warning", class: "hidden px-3 py-2 bg-red-50 border border-red-300 text-red-800 text-[24px] rounded-lg")
      dl(id: "bpus-calc-grid", class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-[24px]")
      div(id: "bpus-scenario", class: "text-[24px] space-y-1")
    end
  end

  # ---------------------------------------------------------------------------
  # §7 靜態注意事項
  # ---------------------------------------------------------------------------
  def render_notes
    div(class: "p-4 bg-gray-50 border border-gray-200 rounded-lg text-[26px] text-gray-600 space-y-1.5") do
      h2(class: "text-sm font-semibold text-gray-700 mb-1") { plain "注意事項" }
      NOTES.each { |n| p { plain n } }
    end
  end

  NOTES = [
    "1. 必須以單一 spread order 下單：兩腿分開成交，券商可能按裸賣 Put 計押金，三級帳戶甚至會被拒單。",
    "2. 提前指派風險：Short Put 進入 ITM（尤其深 ITM、剩餘時間價值極低時）可能被提前指派；被指派後保護腳仍在，最大虧損不變，但需要資金或融資承接股票再處理。",
    "3. 財報與 IV：跨財報的價差需預期 IV crush 與跳空；權利金厚通常代表事件風險高。",
    "4. 流動性：遠 OTM 保護腳 spread 常常很寬，實際成交價可能明顯差於畫面估算；OI 過低的 strike 慎選。",
    "5. 寬價差陷阱：width-based 押金可能高於四級裸賣的公式押金；三級的甜蜜點在窄價差。",
    "6. 到期日風險(pin risk)：到期日股價貼著 short strike 時，是否被指派有不確定性，建議到期前主動平倉或 roll。",
    "7. 資料來源為 Barchart 頁面快照(延遲報價)，僅供試算，非下單依據。"
  ].freeze

  # ---------------------------------------------------------------------------
  # 選腳 hover/press 高亮：原本選腳完全沒有 hover 回饋，使用者不知道現在在選
  # 哪一腳、也不知道列可以點。用 #bpus-chain-table 上的 phase class（JS 依選取
  # 狀態切換）決定 hover 顏色——選保護腳階段淺藍、選 CSP 腳階段淺紅，按下時加深；
  # 已選定的列(.bpus-selected)不參與 hover，避免選完後再滑過去顏色被蓋掉。
  def render_hover_style
    style { raw <<~CSS.html_safe }
      #bpus-chain-table.bpus-phase-protection tr[data-bpus-row]:not(.bpus-selected):hover {
        background-color: #dbeafe;
      }
      #bpus-chain-table.bpus-phase-protection tr[data-bpus-row]:not(.bpus-selected):active {
        background-color: #93c5fd;
      }
      #bpus-chain-table.bpus-phase-csp tr[data-bpus-row]:not(.bpus-selected):hover {
        background-color: #fee2e2;
      }
      #bpus-chain-table.bpus-phase-csp tr[data-bpus-row]:not(.bpus-selected):active {
        background-color: #fecaca;
      }
    CSS
  end

  # 欄位教學三層互動（沿用 LEAPS leaps-column-tooltips-spec.md 同一套 hover
  # tooltip + 點擊聚光 popover 機制，見 LeapsRecommendations::PageComponent
  # #render_tooltips_script；BPUS 只有表頭沒有導覽 tour/術語字卡，故省略）。
  # COLUMN_EXPLAIN 是文案唯一來源，hover 與點擊 popover 共用同一份。
  def render_tooltips_script
    tooltips_script_js
  end

  def tooltips_script_js
    # JavaScript 已搬到 app/frontend/behaviors/bullPutTooltips.js（稽核 H-3 Wave 3）。
    # 路由與頁面狀態改用 data-config JSON 傳入（保留 null 與數值型別）。
    div(
      data: {
        behavior: "bull-put-tooltips",
        config:   {
          symbol:     @symbol,
          expiration: @expiration,
          colExplain: JSON.parse(bpus_col_explain_json),
          routes:     {
            index:            bull_put_spreads_path,
            status:           bull_put_spreads_status_path,
            fetchExpirations: bull_put_spreads_fetch_expirations_path,
            fetchChain:       bull_put_spreads_fetch_chain_path,
            volatility:       bull_put_spreads_volatility_path,
            calculate:        bull_put_spreads_calculate_path
          }
        }.to_json
      }
    )
  end

  def bpus_col_explain_json
    COLUMN_EXPLAIN.transform_values { |v| { title: v[:title], desc: v[:desc] } }.to_json
  end

  # ---------------------------------------------------------------------------
  # JS：fetch_expirations / fetch_chain job 輪詢 + 選腳互動 + calculate
  # ---------------------------------------------------------------------------
  def render_script
    script_js
  end

  def script_js
    # JavaScript 已搬到 app/frontend/behaviors/bullPutSpreads.js（稽核 H-3 Wave 3）。
    # 路由與頁面狀態改用 data-config JSON 傳入（保留 null 與數值型別）。
    div(
      data: {
        behavior: "bull-put-spreads",
        config:   {
          symbol:     @symbol,
          expiration: @expiration,
          colExplain: JSON.parse(bpus_col_explain_json),
          routes:     {
            index:            bull_put_spreads_path,
            status:           bull_put_spreads_status_path,
            fetchExpirations: bull_put_spreads_fetch_expirations_path,
            fetchChain:       bull_put_spreads_fetch_chain_path,
            volatility:       bull_put_spreads_volatility_path,
            calculate:        bull_put_spreads_calculate_path
          }
        }.to_json
      }
    )
  end
end
