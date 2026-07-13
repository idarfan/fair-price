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
      render_symbol_error if @symbol_error
      render_expiration_section if @symbol
      render_chain_section if @expiration && @chain_status
      render_notes
    end
    render_script
  end

  private

  # ---------------------------------------------------------------------------
  # Header / Step1
  # ---------------------------------------------------------------------------
  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") { plain "牛市差價看跌期權(三級版)" }
      p(class: "text-sm text-gray-500 mt-0.5") do
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
        render_calc_panel
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

  def render_chain_table
    div(class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 3/4 · 先選保護腳(藍)，再選 CSP 腳(紅)" }
      p(class: "text-xs text-gray-500") do
        plain "保守計價：賣方取 bid、買方取 ask，以最不利成交價估算，實際可用 mid 價掛單"
      end
      div(class: "overflow-x-auto border border-gray-200 rounded-lg") do
        table(id: "bpus-chain-table", class: "min-w-full text-sm") do
          thead(class: "bg-gray-50 text-gray-500 text-xs uppercase") do
            tr do
              th(class: "px-3 py-2 text-left") { plain "Strike" }
              th(class: "px-3 py-2 text-right") { plain "Bid" }
              th(class: "px-3 py-2 text-right") { plain "Ask" }
              th(class: "px-3 py-2 text-right") { plain "IV" }
              th(class: "px-3 py-2 text-right") { plain "Delta" }
              th(class: "px-3 py-2 text-right") { plain "OI" }
            end
          end
          tbody do
            @put_chain.each_with_index { |row, i| render_chain_row(row, i) }
          end
        end
      end
      p(class: "text-xs") do
        a(href: "#", id: "bpus-reset-legs", class: "text-blue-600 hover:underline") { plain "清空已選腳" }
      end
    end
  end

  def render_chain_row(row, index)
    strike = row["strike"].to_f
    bid    = row["bid"]
    ask    = row["ask"]
    no_quote = bid.nil? && ask.nil?

    row_class = (index.odd? ? "bg-gray-50/50" : "") + " border-t border-gray-100"
    row_class += " opacity-40 pointer-events-none" if no_quote

    tr(
      class: row_class,
      data: {
        "bpus-row": "",
        strike: strike,
        bid: bid,
        ask: ask,
        iv: row["iv"],
        delta: row["delta"]
      }
    ) do
      td(class: "px-3 py-1.5 font-medium text-gray-900") { plain sprintf("%.2f", strike) }
      td(class: "px-3 py-1.5 text-right") { plain bid.nil? ? "—" : sprintf("%.2f", bid.to_f) }
      td(class: "px-3 py-1.5 text-right") { plain ask.nil? ? "—" : sprintf("%.2f", ask.to_f) }
      td(class: "px-3 py-1.5 text-right text-gray-500") { plain row["iv"] ? sprintf("%.1f%%", row["iv"].to_f * 100) : "—" }
      td(class: "px-3 py-1.5 text-right text-gray-500") { plain row["delta"] ? sprintf("%.2f", row["delta"].to_f) : "—" }
      td(class: "px-3 py-1.5 text-right text-gray-500") { plain row["open_interest"] || "—" }
    end
  end

  def render_calc_panel
    div(id: "bpus-calc-panel", class: "hidden space-y-3 p-4 bg-white border border-gray-200 rounded-lg") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "Step 5 · 計算結果" }
      div(id: "bpus-calc-warning", class: "hidden px-3 py-2 bg-red-50 border border-red-300 text-red-800 text-sm rounded-lg")
      dl(id: "bpus-calc-grid", class: "grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm")
      div(id: "bpus-scenario", class: "text-sm space-y-1")
    end
  end

  # ---------------------------------------------------------------------------
  # §7 靜態注意事項
  # ---------------------------------------------------------------------------
  def render_notes
    div(class: "p-4 bg-gray-50 border border-gray-200 rounded-lg text-xs text-gray-600 space-y-1.5") do
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

        // ── Step1: 送出代號 → 抓履約日 ──────────────────────────────────────
        var form = document.getElementById('bpus-symbol-form');
        var inp  = document.getElementById('bpus-symbol-input');
        if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });

        function fetchExpirations(symbol) {
          var loading = document.getElementById('bpus-loading');
          if (loading) loading.classList.remove('hidden');
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

        function clearHighlight(row) {
          row.classList.remove('bg-blue-50', 'border-blue-400', 'bg-red-50', 'border-red-400');
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
          var panel = document.getElementById('bpus-calc-panel');
          if (panel) panel.classList.add('hidden');
        }

        function rowData(row) {
          return {
            strike: parseFloat(row.getAttribute('data-strike')),
            bid: parseFloat(row.getAttribute('data-bid')),
            ask: parseFloat(row.getAttribute('data-ask'))
          };
        }

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

          grid.innerHTML =
            '<div><dt class="text-xs text-gray-500">淨權利金收入</dt><dd class="font-semibold">$' + fmt(d.net_credit) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">價差寬度</dt><dd class="font-semibold">' + fmt(d.width) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">$' + fmt(d.max_profit) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">最大虧損 / 押金</dt><dd class="font-semibold text-red-700">$' + fmt(d.max_loss) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">損益平衡點</dt><dd class="font-semibold">$' + fmt(d.breakeven) + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">ROC</dt><dd class="font-semibold text-yellow-700">' + (d.roc === null ? '—' : d.roc + '%') + '</dd></div>' +
            '<div><dt class="text-xs text-gray-500">風險報酬比</dt><dd class="font-semibold">' + (d.risk_reward === null ? '—' : '1 : ' + d.risk_reward) + '</dd></div>';

          if (d.warning !== 'invalid_width') {
            scen.innerHTML =
              '<p>🌞 股價 ≥ $' + fmt(d.short_strike) + '：全額獲利 = $' + fmt(d.net_credit) + '</p>' +
              '<p>🧊 股價介於 $' + fmt(d.long_strike) + ' ~ $' + fmt(d.breakeven) + '：開始賠錢</p>' +
              '<p>🥶 股價 ≤ $' + fmt(d.long_strike) + '：最大虧損鎖定 = $' + fmt(d.max_loss) + '</p>';
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
              row.classList.add('bg-blue-50', 'border-blue-400');
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
              row.classList.add('bg-red-50', 'border-red-400');
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
