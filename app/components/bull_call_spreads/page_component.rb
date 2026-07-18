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
  # Header / Level 3 banner / Step1
  # ---------------------------------------------------------------------------
  def render_level3_banner
    div(class: "px-4 py-2 bg-amber-50 border border-amber-300 text-amber-900 text-xs font-medium rounded-lg") do
      plain "⚠️ 本策略含賣出期權腳，需三級（Level 3）期權交易權限方可開設"
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
    div(class: "space-y-2") do
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
    "moneyness" => {
      title: "Moneyness（價內外程度）",
      desc: "(現價−履約價)/現價 的百分比。正值代表 Call 為價內(ITM)，負值代表價外(OTM)。"
    },
    "bid" => {
      title: "Bid（買方出價）",
      desc: "市場上買方目前願意支付的最高價格。K2（賣出腳）以 Bid 掛單可立即成交，本頁「賣方取 bid」即採用這個保守估算。"
    },
    "mid" => {
      title: "Mid（中價）",
      desc: "(Bid+Ask)/2，市場中間價。實際下單建議掛 Mid 價、耐心等候撮合成交，通常能拿到比保守估算更好的價格。"
    },
    "ask" => {
      title: "Ask（賣方要價）",
      desc: "市場上賣方目前願意賣出的最低價格。K1（買進腳）以 Ask 掛單可立即成交，本頁「買方取 ask」即採用這個保守估算。"
    },
    "last" => {
      title: "Last（最後成交價）",
      desc: "這個履約價最近一次實際成交的價格，成交量少的履約價這個數字參考價值較低。"
    },
    "change" => {
      title: "Change（漲跌）",
      desc: "這個履約價的權利金比前一交易日收盤價變動了多少（絕對金額）。unch 代表今天完全沒有成交。"
    },
    "pct_change" => {
      title: "%Change（漲跌幅）",
      desc: "權利金變動的百分比。選擇權基期價格通常很小，建議搭配 Change 絕對金額一起看。"
    },
    "volume" => {
      title: "Volume（成交量）",
      desc: "當日這個履約價實際成交的口數。量越大代表流動性越好，成交價越貼近真實市場共識。"
    },
    "open_interest" => {
      title: "OI（未平倉量）",
      desc: "目前市場上尚未平倉的合約總口數。OI 過低代表流動性差，實際成交價可能明顯偏離畫面估算。"
    },
    "oi_change" => {
      title: "OI Chg（未平倉量變化）",
      desc: "跟前一交易日相比，未平倉量增加或減少了多少。"
    },
    "iv" => {
      title: "IV（隱含波動率）",
      desc: "市場對這個履約價未來波動幅度的預期，數字越高代表市場預期波動越劇烈、權利金越貴。財報前 IV 通常會墊高，財報後容易 IV crush。"
    },
    "delta" => {
      title: "Delta（避險比率）",
      desc: "股價變動 $1 時，這個 Call 權利金理論上變動多少，也常被當作「到期價內機率」的粗略估計。"
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
      render_repair_panel
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

  # ---------------------------------------------------------------------------
  # 修復模式（bcvs.md §修復模式，選配輸入）
  # ---------------------------------------------------------------------------
  def render_repair_panel
    details(class: "border border-gray-200 rounded-lg") do
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
  def render_notes
    div(class: "p-4 bg-gray-50 border border-gray-200 rounded-lg text-[26px] text-gray-600 space-y-3") do
      div do
        h2(class: "text-sm font-semibold text-gray-700 mb-1") { plain "好處" }
        p { plain "成本低於裸買 call、最大損失封頂於淨成本、賣腳權利金部分對沖 theta、修復模式可壓縮虧損 LEAPS 在橫盤～小漲區間的損失。" }
      end
      div do
        h2(class: "text-sm font-semibold text-gray-700 mb-1") { plain "注意事項" }
        NOTES.each { |n| p { plain n } }
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

  # ---------------------------------------------------------------------------
  # 選 K1 hover 高亮（沿用 bpus 的 phase class 機制，這裡只有一個選取階段）
  # ---------------------------------------------------------------------------
  def render_hover_style
    style { raw <<~CSS.html_safe }
      #bcvs-chain-table tr:hover {
        background-color: #dbeafe;
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
          }
        });
      })();
    JS
  end

  def bcvs_col_explain_json
    COLUMN_EXPLAIN.transform_values { |v| { title: v[:title], desc: v[:desc] } }.to_json
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
          grid.innerHTML =
            '<div><dt class="text-[24px] text-gray-500">K2</dt><dd class="font-semibold">$' + fmt(tab.k2) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">淨成本(debit)</dt><dd class="font-semibold">' + fmtLots(tab.cost_per_contract, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">' + fmtLots(tab.max_profit, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">最大損失</dt><dd class="font-semibold text-red-700">' + fmtLots(tab.max_loss, lots) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">損益兩平</dt><dd class="font-semibold">$' + fmt(tab.breakeven) + '</dd></div>' +
            '<div><dt class="text-[24px] text-gray-500">報酬風險比</dt><dd class="font-semibold text-yellow-700">' + (tab.risk_reward === null ? '—' : tab.risk_reward) + '</dd></div>';

          fillRepairFromTab(tab);
        }

        document.querySelectorAll('[data-bcvs-recommend-tab]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            setActiveTab(btn.getAttribute('data-bcvs-recommend-tab'));
          });
        });

        var lotsInput = document.getElementById('bcvs-lots-input');
        if (lotsInput) lotsInput.addEventListener('input', renderTab);

        function runRecommend(k1, k1Ask) {
          fetch('#{bull_call_spreads_recommend_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({ symbol: #{@symbol.to_json}, expiration: #{@expiration.to_json}, k1: k1, k1_ask: k1Ask })
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
            runRecommend(parseFloat(opt.value), parseFloat(opt.getAttribute('data-ask')));
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

          fetch('#{bull_call_spreads_calculate_path}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify(payload)
          })
          .then(function (r) { return r.json(); })
          .then(renderRepairResult)
          .catch(function () {});
        }

        function renderRepairResult(d) {
          var resultEl = document.getElementById('bcvs-repair-result');
          if (!resultEl) return;
          resultEl.classList.remove('hidden');

          var warningHtml = '';
          if (d.warning === 'locked_loss') {
            warningHtml = '<p class="text-red-700 font-semibold">⚠️ 此組合鎖定虧損 $' + fmt(Math.abs(d.locked_result_total)) + '／口（basis 需 ≤ $' + fmt(d.breakeven_basis) + ' 才不虧損）</p>';
          }

          var closeoutHtml = '';
          if (d.closeout_pnl !== null && d.closeout_pnl !== undefined) {
            closeoutHtml = '<p>對照現在直接平倉：收回 $' + fmt(d.closeout_proceeds) + '（損益 $' + fmt(d.closeout_pnl) + '）</p>';
          }

          resultEl.innerHTML =
            warningHtml +
            '<p>≥K2 鎖定結果：$' + fmt(d.locked_result_total) + '／口（分水嶺 basis = $' + fmt(d.breakeven_basis) + '）</p>' +
            '<p>≤K1 情境：$' + fmt(d.below_k1_pnl_total) + '／口</p>' +
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
