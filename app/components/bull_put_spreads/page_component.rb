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
      button(type: "button", class: "px-3 py-1.5 rounded-lg text-xs font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
             data: { "bpus-recommend-tab": "conservative" }) { plain "保守收租" }
      button(type: "button", class: "px-3 py-1.5 rounded-lg text-xs font-medium bg-white border border-gray-300 text-gray-700 hover:border-blue-400",
             data: { "bpus-recommend-tab": "aggressive" }) { plain "激進收租" }
    end
    div(id: "bpus-recommend-explain", class: "hidden mt-2 px-3 py-2 bg-yellow-50 border border-yellow-200 text-yellow-900 text-[24px] rounded-lg")
    div(id: "bpus-volatility-explain", class: "hidden mt-2 px-3 py-2 bg-indigo-50 border border-indigo-200 text-indigo-900 text-xs rounded-lg")
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
        label(class: "flex items-center gap-2 text-xs text-gray-600") do
          plain "口數"
          input(type: "number", id: "bpus-lots-input", value: "1", min: "1", step: "1",
                class: "w-16 border border-gray-300 rounded px-2 py-1 text-right")
        end
      end
      div(id: "bpus-calc-warning", class: "hidden px-3 py-2 bg-red-50 border border-red-300 text-red-800 text-sm rounded-lg")
      dl(id: "bpus-calc-grid", class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm")
      div(id: "bpus-scenario", class: "text-sm space-y-1")
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
    script { raw tooltips_script_js.html_safe }
  end

  def tooltips_script_js
    <<~JS
      (function () {
        var BPUS_COL_EXPLAIN = #{bpus_col_explain_json};

        var tip = document.createElement('div');
        tip.id = 'bpus-col-tip';
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
            var d = BPUS_COL_EXPLAIN[el.dataset.tipKey];
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
            var d = BPUS_COL_EXPLAIN[el.dataset.tipKey];
            if (!d) return;
            tip.style.opacity = '0';
            drv()({ animate: true, allowClose: true, overlayOpacity: 0.35,
                    steps: [{ element: el, popover: { title: d.title, description: d.desc, side: 'bottom', align: 'center' } }] }).drive();
          }
        });
      })();
    JS
  end

  def bpus_col_explain_json
    COLUMN_EXPLAIN.transform_values { |v| { title: v[:title], desc: v[:desc] } }.to_json
  end

  # ---------------------------------------------------------------------------
  # JS：fetch_expirations / fetch_chain job 輪詢 + 選腳互動 + calculate
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

        function pollJob(jobId, onDone) {
          var attempts = 0;
          var timer = setInterval(function () {
            if (++attempts > 60) { clearInterval(timer); onDone('error'); return; }
            fetch('#{bull_put_spreads_status_path}?job_id=' + jobId)
              .then(function (r) { return r.json(); })
              .then(function (d) {
                if (d.status === 'pending' || d.status === 'not_found') return;
                clearInterval(timer);
                onDone(d.status);
              }).catch(function () {});
          }, 2000);
        }

        // ── 進度條：抓履約日／Put 鏈共用 ─────────────────────────────────────
        function showProgress() {
          var bar = document.getElementById('bpus-progress');
          if (bar) bar.classList.remove('hidden');
        }
        function hideProgress() {
          var bar = document.getElementById('bpus-progress');
          if (bar) bar.classList.add('hidden');
        }

        // ── Step1: 送出代號 → 抓履約日 ──────────────────────────────────────
        var form = document.getElementById('bpus-symbol-form');
        var inp  = document.getElementById('bpus-symbol-input');
        if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });

        function fetchExpirations(symbol) {
          var loading = document.getElementById('bpus-loading');
          if (loading) loading.classList.remove('hidden');
          showProgress();
          var submitBtn = document.getElementById('bpus-submit-btn');
          var retryBtnEl = document.getElementById('bpus-fetch-expirations-btn');
          if (submitBtn) submitBtn.disabled = true;
          if (retryBtnEl) retryBtnEl.disabled = true;
          fetch('#{bull_put_spreads_fetch_expirations_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({ symbol: symbol })
          })
          .then(function (r) { return r.json(); })
          .then(function (d) {
            if (d.status === 'ready') {
              window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol;
            } else if (d.status === 'cdp_offline') {
              window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol + '&job_status=cdp_offline';
            } else if (d.job_id) {
              pollJob(d.job_id, function (status) {
                window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol + '&job_status=' + status;
              });
            } else {
              window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol + '&job_status=error';
            }
          }).catch(function () {
            window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol + '&job_status=error';
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

        var retryBtn = document.getElementById('bpus-fetch-expirations-btn');
        if (retryBtn) {
          retryBtn.addEventListener('click', function () {
            fetchExpirations(#{@symbol.to_json});
          });
        }

        // ── Step2: 點履約日 → 抓 Put 鏈 ──────────────────────────────────────
        document.querySelectorAll('[data-bpus-expiration-btn]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            var exp = btn.getAttribute('data-exp');
            var symbol = #{@symbol.to_json};
            showProgress();
            document.querySelectorAll('[data-bpus-expiration-btn]').forEach(function (b) { b.disabled = true; });
            fetch('#{bull_put_spreads_fetch_chain_path}', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
              body: JSON.stringify({ symbol: symbol, expiration: exp })
            })
            .then(function (r) { return r.json(); })
            .then(function (d) {
              var base = '#{bull_put_spreads_path}?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp);
              if (d.status === 'ready') {
                window.location.href = base;
              } else if (d.status === 'cdp_offline') {
                window.location.href = base + '&chain_job_status=cdp_offline';
              } else if (d.job_id) {
                pollJob(d.job_id, function (status) { window.location.href = base + '&chain_job_status=' + status; });
              } else {
                window.location.href = base + '&chain_job_status=error';
              }
            }).catch(function () {
              window.location.href = '#{bull_put_spreads_path}?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp) + '&chain_job_status=error';
            });
          });
        });

        // ── Step3/4: 選腳互動 ────────────────────────────────────────────────
        var state = { protection: null, csp: null };

        // 用 !important 變體(!bg-blue-50 等)蓋過列本身的斑馬紋 bg-gray-50/50——
        // 兩者都是同層級 utility class，DOM classList 加入順序不影響 CSS
        // cascade，實測發現奇數列(有斑馬紋)加了 bg-red-50/bg-blue-50 仍被斑馬紋
        // 蓋掉、完全看不到標色(bpus-fix.md 項目3)。!important 變體確保一定蓋過。
        function clearHighlight(row) {
          row.classList.remove('!bg-blue-50', '!border-blue-400', '!bg-red-50', '!border-red-400', 'bpus-selected');
        }

        function setPhase(phase) {
          var table = document.getElementById('bpus-chain-table');
          if (!table) return;
          table.classList.toggle('bpus-phase-protection', phase === 'protection');
          table.classList.toggle('bpus-phase-csp', phase === 'csp');
        }

        // kind 為 null 時兩個分頁都恢復未選取樣式。
        function setActiveTab(kind) {
          document.querySelectorAll('[data-bpus-recommend-tab]').forEach(function (btn) {
            var active = btn.getAttribute('data-bpus-recommend-tab') === kind;
            btn.classList.toggle('bg-blue-600', active);
            btn.classList.toggle('text-white', active);
            btn.classList.toggle('border-blue-600', active);
            btn.classList.toggle('bg-white', !active);
            btn.classList.toggle('text-gray-700', !active);
            btn.classList.toggle('border-gray-300', !active);
          });
        }

        function hideRecommendExplain() {
          var el = document.getElementById('bpus-recommend-explain');
          if (el) { el.classList.add('hidden'); el.textContent = ''; }
          var volEl = document.getElementById('bpus-volatility-explain');
          if (volEl) { volEl.classList.add('hidden'); volEl.textContent = ''; }
          activeRecommendKind = null;
          setActiveTab(null);
        }

        // ── 波動率背景資料(bpus-fix.md 項目6)：頁面載入後背景輪詢，抓到才顯示，
        // 不阻塞履約日/Put 鏈這條主流程；抓不到就靜靜維持隱藏，不報錯打擾使用者。
        var lastVolatility = null;
        var activeRecommendKind = null;

        function renderVolatilityExplain() {
          var volEl = document.getElementById('bpus-volatility-explain');
          if (!volEl || !activeRecommendKind || !lastVolatility || lastVolatility.status !== 'success') return;
          var v = lastVolatility;
          var levelNote = v.iv >= 80
            ? 'IV 偏高：權利金較厚、ROC 較有吸引力，但要留意財報後或事件後的 IV crush 侵蝕權利金價值。'
            : (v.iv <= 40
              ? 'IV 偏低：權利金較薄，同樣寬度的價差 ROC 會偏低，賣方吸引力較弱。'
              : 'IV 中等：權利金與 ROC 落在一般水準。');
          var rankNote = (typeof v.iv_rank === 'number')
            ? '目前 IV Rank ' + v.iv_rank.toFixed(1) + '%（相對自身歷史的百分位）' +
              (v.iv_rank >= 50 ? '，處於相對高檔，賣方（收租）策略相對有利。' : '，處於相對低檔，賣方拿到的權利金相對單薄。')
            : '';
          var kindLabel = activeRecommendKind === 'conservative' ? '保守收租' : '激進收租';
          volEl.classList.remove('hidden');
          volEl.textContent = '📊 ' + kindLabel + ' × 目前波動率：IV ' + fmt(v.iv) + '%、HV ' + fmt(v.hv) + '%。' +
            levelNote + rankNote;
        }

        function fetchVolatility(symbol, expiration) {
          fetch('#{bull_put_spreads_volatility_path}?symbol=' + encodeURIComponent(symbol) + '&expiration=' + encodeURIComponent(expiration))
            .then(function (r) { return r.json(); })
            .then(function (d) {
              if (d.status === 'pending') {
                setTimeout(function () { fetchVolatility(symbol, expiration); }, 4000);
              } else {
                lastVolatility = d;
                renderVolatilityExplain();
              }
            }).catch(function () {});
        }

        if (document.getElementById('bpus-chain-table') && #{@expiration.to_json}) {
          fetchVolatility(#{@symbol.to_json}, #{@expiration.to_json});
        }

        function resetSelection() {
          state.protection = null;
          state.csp = null;
          document.querySelectorAll('[data-bpus-row]').forEach(function (row) {
            clearHighlight(row);
            row.classList.remove('opacity-40', 'pointer-events-none');
            if (row.getAttribute('data-bid') === '' || row.getAttribute('data-bid') === null) {
              // 保持原本無報價列的禁用狀態不變（由後端 render 決定）
            }
          });
          setPhase('protection');
          hideRecommendExplain();
          var panel = document.getElementById('bpus-calc-panel');
          if (panel) panel.classList.add('hidden');
          var legsPanel = document.getElementById('bpus-selected-legs');
          if (legsPanel) legsPanel.classList.add('hidden');
          [ 'bpus-protection-row', 'bpus-csp-row' ].forEach(function (id) {
            var row = document.getElementById(id);
            if (row) row.classList.add('hidden');
          });
        }

        // 跟 Ruby 端 COLUMNS 常數(app/components/bull_put_spreads/page_component.rb)
        // 保持同一份欄位清單——表格 data-* 屬性、選腳明細列的 data-field，都用這份
        // key 對應，避免兩處各自維護漂移。
        var COLUMN_KEYS = [ 'strike', 'moneyness', 'bid', 'mid', 'ask', 'last',
          'change', 'pct_change', 'volume', 'open_interest', 'oi_change', 'iv', 'delta' ];

        function attrName(key) { return 'data-' + key.replace(/_/g, '-'); }

        function rowData(row) {
          var d = {};
          COLUMN_KEYS.forEach(function (k) { d[k] = parseFloat(row.getAttribute(attrName(k))); });
          return d;
        }

        function fmtField(key, v) {
          var isDelta = (key === 'change' || key === 'pct_change' || key === 'oi_change');
          if (isNaN(v)) return isDelta ? 'unch' : '—';
          if (isDelta && v === 0) return 'unch';
          switch (key) {
            case 'strike': case 'bid': case 'mid': case 'ask': case 'last':
              return v.toFixed(2);
            case 'moneyness':
              return (v * 100).toFixed(2) + '%';
            case 'iv':
              return (v * 100).toFixed(1) + '%';
            case 'delta':
              return v.toFixed(2);
            case 'change':
              return (v >= 0 ? '+' : '') + v.toFixed(2);
            case 'pct_change':
              return (v >= 0 ? '+' : '') + (v * 100).toFixed(2) + '%';
            case 'oi_change':
              return (v >= 0 ? '+' : '') + v;
            default:
              return v;
          }
        }

        // 完整呈現讀到的 Barchart 原始資料（不重算、不篩選欄位），選一腳就立刻長一排。
        function fillLegRow(rowId, data) {
          var row = document.getElementById(rowId);
          if (!row) return;
          var legsPanel = document.getElementById('bpus-selected-legs');
          if (legsPanel) legsPanel.classList.remove('hidden');
          row.classList.remove('hidden');
          COLUMN_KEYS.forEach(function (k) {
            var cell = row.querySelector('[data-field="' + k + '"]');
            if (cell) cell.textContent = fmtField(k, data[k]);
          });
        }

        // 保守/激進收租建議：從已渲染的表格挑兩腳，不用額外打後端。
        // CSP 腳挑 |delta| 最接近目標值的 strike；保護腳挑其下一個「有真實
        // 報價」的 strike（維持窄價差，沿用注意事項§5「三級的甜蜜點在窄價
        // 差」）。iv/volume/oi 同時為 0 的列視為無真實報價的殘影資料，排除。
        var RECOMMEND_TARGETS = { conservative: 0.15, aggressive: 0.30 };

        function isRealQuoteRow(d) {
          var hasQuote = !isNaN(d.bid) || !isNaN(d.ask);
          var isGhost = d.iv === 0 && d.volume === 0 && d.open_interest === 0;
          return hasQuote && !isGhost;
        }

        function collectValidRows() {
          return [ ...document.querySelectorAll('[data-bpus-row]') ]
            .map(function (r) { return { el: r, data: rowData(r) }; })
            .filter(function (x) { return isRealQuoteRow(x.data); })
            .sort(function (a, b) { return a.data.strike - b.data.strike; });
        }

        function findRecommendation(targetAbsDelta) {
          var rows = collectValidRows();
          var shortCandidate = null;
          var shortDiff = Infinity;
          rows.forEach(function (r) {
            if (isNaN(r.data.delta)) return;
            var diff = Math.abs(Math.abs(r.data.delta) - targetAbsDelta);
            if (diff < shortDiff) { shortDiff = diff; shortCandidate = r; }
          });
          if (!shortCandidate) return null;

          var lower = rows.filter(function (r) { return r.data.strike < shortCandidate.data.strike; });
          if (!lower.length) return null;
          var protectionCandidate = lower[lower.length - 1]; // 最接近的下一個 strike = 最窄價差

          return { protection: protectionCandidate, short: shortCandidate };
        }

        function applyRecommendation(kind) {
          resetSelection();
          var rec = findRecommendation(RECOMMEND_TARGETS[kind]);
          var explainEl = document.getElementById('bpus-recommend-explain');
          if (!rec) {
            if (explainEl) {
              explainEl.classList.remove('hidden');
              explainEl.textContent = '此履約日的期權鏈找不到符合條件的建議組合（報價或 Delta 資料不足），請手動選腳。';
            }
            return;
          }
          setActiveTab(kind);

          var pRow = rec.protection.el, pData = rec.protection.data;
          state.protection = Object.assign({ row: pRow }, pData);
          clearHighlight(pRow);
          pRow.classList.add('!bg-blue-50', '!border-blue-400', 'bpus-selected');
          fillLegRow('bpus-protection-row', pData);
          setPhase('csp');
          document.querySelectorAll('[data-bpus-row]').forEach(function (r) {
            var rd = rowData(r);
            if (r !== pRow && rd.strike <= pData.strike) r.classList.add('opacity-40', 'pointer-events-none');
          });

          var sRow = rec.short.el, sData = rec.short.data;
          state.csp = Object.assign({ row: sRow }, sData);
          clearHighlight(sRow);
          sRow.classList.add('!bg-red-50', '!border-red-400', 'bpus-selected');
          fillLegRow('bpus-csp-row', sData);
          runCalculate();

          if (explainEl) {
            var label       = kind === 'conservative' ? '保守收租' : '激進收租';
            var targetLabel = kind === 'conservative' ? '-0.15' : '-0.30';
            var profile     = kind === 'conservative'
              ? '較遠價外、勝率較高但權利金較低，適合重視安全邊際的收租策略。'
              : '較接近價平、權利金較高但勝率較低、被指派機率較高，適合追求更高 ROC 的積極策略。';
            explainEl.classList.remove('hidden');
            explainEl.textContent = label + '建議：CSP 腳選 |Delta| 最接近 ' + targetLabel + ' 的履約價 $' +
              fmt(sData.strike) + '（實際 Delta ' + sData.delta.toFixed(2) + '），保護腳取其下一個有報價的履約價 $' +
              fmt(pData.strike) + '，維持窄價差以降低押金；' + profile;
          }

          activeRecommendKind = kind;
          renderVolatilityExplain();
        }

        document.querySelectorAll('[data-bpus-recommend-tab]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            applyRecommendation(btn.getAttribute('data-bpus-recommend-tab'));
          });
        });

        function runCalculate() {
          fetch('#{bull_put_spreads_calculate_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({
              short_strike: state.csp.strike, short_bid: state.csp.bid,
              long_strike: state.protection.strike, long_ask: state.protection.ask
            })
          })
          .then(function (r) { return r.json(); })
          .then(renderCalcResult)
          .catch(function () {});
        }

        function fmt(n) { return (typeof n === 'number' && !isNaN(n)) ? n.toFixed(2) : '—'; }

        // 口數：金額類結果用「單口 × 口數 = 總計」呈現；BE/ROC/風險報酬比是
        // 比率，不隨口數變化，維持單口顯示(bpus-fix.md 項目5)。
        function currentLots() {
          var el = document.getElementById('bpus-lots-input');
          var n = el ? parseInt(el.value, 10) : 1;
          return (!n || n < 1) ? 1 : n;
        }

        function fmtLots(perLot, lots) {
          if (typeof perLot !== 'number' || isNaN(perLot)) return '—';
          if (lots <= 1) return '$' + fmt(perLot);
          return '$' + fmt(perLot) + ' × ' + lots + ' = $' + fmt(perLot * lots);
        }

        var lastCalcResult = null;

        function runCalculate() {
          fetch('#{bull_put_spreads_calculate_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({
              short_strike: state.csp.strike, short_bid: state.csp.bid,
              long_strike: state.protection.strike, long_ask: state.protection.ask
            })
          })
          .then(function (r) { return r.json(); })
          .then(function (d) { lastCalcResult = d; renderCalcResult(d); })
          .catch(function () {});
        }

        var lotsInput = document.getElementById('bpus-lots-input');
        if (lotsInput) {
          lotsInput.addEventListener('input', function () {
            if (lastCalcResult) renderCalcResult(lastCalcResult);
          });
        }

        function renderCalcResult(d) {
          var panel = document.getElementById('bpus-calc-panel');
          var grid  = document.getElementById('bpus-calc-grid');
          var warn  = document.getElementById('bpus-calc-warning');
          var scen  = document.getElementById('bpus-scenario');
          if (!panel || !grid) return;
          panel.classList.remove('hidden');

          if (d.warning === 'debit') {
            warn.textContent = '⚠️ 此組合為 debit，非收租結構';
            warn.classList.remove('hidden');
          } else if (d.warning === 'invalid_width') {
            warn.textContent = '⚠️ CSP 腳的履約價必須高於保護腳';
            warn.classList.remove('hidden');
          } else {
            warn.classList.add('hidden');
          }

          var lots = currentLots();

          // 提前指派所需現金：CSP 履約價 × 100 × 口數；括號附註扣除已收
          // 權利金(net_credit，已隨口數放大)後的淨成本(bpus-fix.md 項目4)。
          var assignCashHtml = '—';
          if (d.warning !== 'invalid_width' && typeof d.short_strike === 'number') {
            var cashTotal = d.short_strike * 100 * lots;
            var netCreditTotal = (typeof d.net_credit === 'number' ? d.net_credit : 0) * lots;
            var netCost = cashTotal - netCreditTotal;
            assignCashHtml = '$' + fmt(cashTotal) + '（淨成本 $' + fmt(netCost) + '）';
          }

          grid.innerHTML =
            '<div><dt class="text-xs text-gray-500">淨權利金收入</dt><dd class="font-semibold">' + fmtLots(d.net_credit, lots) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">價差寬度</dt><dd class="font-semibold">' + fmt(d.width) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">' + fmtLots(d.max_profit, lots) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">最大虧損 / 押金</dt><dd class="font-semibold text-red-700">' + fmtLots(d.max_loss, lots) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">損益平衡點</dt><dd class="font-semibold">$' + fmt(d.breakeven) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">ROC</dt><dd class="font-semibold text-yellow-700">' + (d.roc === null ? '—' : d.roc + '%') + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">風險報酬比</dt><dd class="font-semibold">' + (d.risk_reward === null ? '—' : '1 : ' + d.risk_reward) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">提前指派：承接現金</dt><dd class="font-semibold text-purple-700">' + assignCashHtml + '</dd></div>';

          if (d.warning !== 'invalid_width') {
            scen.innerHTML =
              '<p>🌞 股價 ≥ $' + fmt(d.short_strike) + '：全額獲利 = ' + fmtLots(d.net_credit, lots) + '</p>' +
              '<p>🧊 股價介於 $' + fmt(d.long_strike) + ' ~ $' + fmt(d.breakeven) + '：開始賠錢</p>' +
              '<p>🥶 股價 ≤ $' + fmt(d.long_strike) + '：最大虧損鎖定 = ' + fmtLots(d.max_loss, lots) + '</p>';
          } else {
            scen.innerHTML = '';
          }
        }

        document.querySelectorAll('[data-bpus-row]').forEach(function (row) {
          row.addEventListener('click', function () {
            var data = rowData(row);

            if (state.protection && row === state.protection.row) {
              resetSelection();
              return;
            }

            if (!state.protection) {
              state.protection = Object.assign({ row: row }, data);
              clearHighlight(row);
              row.classList.add('!bg-blue-50', '!border-blue-400', 'bpus-selected');
              fillLegRow('bpus-protection-row', data);
              setPhase('csp');
              document.querySelectorAll('[data-bpus-row]').forEach(function (r) {
                var rd = rowData(r);
                if (r !== row && rd.strike <= data.strike) {
                  r.classList.add('opacity-40', 'pointer-events-none');
                }
              });
              return;
            }

            if (!state.csp && data.strike > state.protection.strike) {
              state.csp = Object.assign({ row: row }, data);
              clearHighlight(row);
              row.classList.add('!bg-red-50', '!border-red-400', 'bpus-selected');
              fillLegRow('bpus-csp-row', data);
              runCalculate();
            }
          });
        });

        var resetLink = document.getElementById('bpus-reset-legs');
        if (resetLink) {
          resetLink.addEventListener('click', function (e) {
            e.preventDefault();
            resetSelection();
          });
        }
      })();
    JS
  end
end
