/**
 * Bull Call Spread 頁：到期日/期權鏈抓取、輪詢、推薦、試算。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_call_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 * TODO：型別化成 .ts；與另一支 spread 頁面之間仍有大量重複（稽核 M-6）。
 */

export function init(root) {
  var CFG = JSON.parse(root.dataset.config);

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

    var CURRENT_PRICE = CFG.underlyingPrice;

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
      fetch(CFG.routes.fetchExpirations, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
        body: JSON.stringify({ symbol: symbol })
      })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (d.status === 'ready') {
          window.location.href = CFG.routes.index + '?symbol=' + symbol;
        } else if (d.status === 'cdp_offline') {
          window.location.href = CFG.routes.index + '?symbol=' + symbol + '&job_status=cdp_offline';
        } else if (d.job_id) {
          pollJob(d.job_id, CFG.routes.status, function (status) {
            window.location.href = CFG.routes.index + '?symbol=' + symbol + '&job_status=' + status;
          });
        } else {
          window.location.href = CFG.routes.index + '?symbol=' + symbol + '&job_status=error';
        }
      }).catch(function () {
        window.location.href = CFG.routes.index + '?symbol=' + symbol + '&job_status=error';
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
        fetchExpirations(CFG.symbol);
      });
    }

    // ── Step2: 點到期日 → 抓 Call 鏈 ─────────────────────────────────────
    document.querySelectorAll('[data-bcvs-expiration-btn]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var exp = btn.getAttribute('data-exp');
        var symbol = CFG.symbol;
        showProgress();
        document.querySelectorAll('[data-bcvs-expiration-btn]').forEach(function (b) { b.disabled = true; });
        fetch(CFG.routes.fetchChain, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
          body: JSON.stringify({ symbol: symbol, expiration: exp })
        })
        .then(function (r) { return r.json(); })
        .then(function (d) {
          var base = CFG.routes.index + '?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp);
          if (d.status === 'ready') {
            window.location.href = base;
          } else if (d.status === 'cdp_offline') {
            window.location.href = base + '&chain_job_status=cdp_offline';
          } else if (d.job_id) {
            pollJob(d.job_id, CFG.routes.status, function (status) { window.location.href = base + '&chain_job_status=' + status; });
          } else {
            window.location.href = base + '&chain_job_status=error';
          }
        }).catch(function () {
          window.location.href = CFG.routes.index + '?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp) + '&chain_job_status=error';
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
      // bcvs.md §字級鐵則 v4：Step 5 標籤 20px、主數字 24px 粗體。
      // K2 徽章（v4 待辦）：橘色邊框 #EF9F27 1.5px、圓角 8px、淡紅底
      // #FDE8E8、紅字 #A32D2D，內距 4px 12px，字級維持 24px 粗體。
      var k2Badge = '<span style="display:inline-block; border:1.5px solid #EF9F27; border-radius:8px; background:#FDE8E8; color:#A32D2D; padding:4px 12px; font-size:24px; font-weight:700;">$' + fmt(tab.k2) + '</span>';
      grid.innerHTML =
        '<div><dt class="text-[20px] text-gray-500">K2</dt><dd class="mt-1">' + k2Badge + '</dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">淨成本 debit</dt><dd class="text-[24px] font-bold">$' + fmt(tab.debit) + '<span class="text-[20px] font-normal">' + debitMidHtml + '</span></dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">每口成本</dt><dd class="text-[24px] font-bold">' + fmtLots(tab.cost_per_contract, lots) + '</dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">最大獲利</dt><dd class="text-[24px] font-bold text-green-700">' + fmtLots(tab.max_profit, lots) + '</dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">最大損失</dt><dd class="text-[24px] font-bold text-red-700">' + fmtLots(tab.max_loss, lots) + '</dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">損益兩平</dt><dd class="text-[24px] font-bold">$' + fmt(tab.breakeven) + '</dd></div>' +
        '<div><dt class="text-[20px] text-gray-500">報酬風險比</dt><dd class="text-[24px] font-bold text-yellow-700">' + (tab.risk_reward === null ? '—' : tab.risk_reward) + '</dd></div>';

      renderIntervalTable(tab, lots);
      renderNakedComparison(tab, lots);
      renderEarlyClose(tab, lots);
      // basis 欄位保留使用者已輸入的值，不覆蓋；runRepairIfReady 自己會從
      // lastTabs[activeTab] 與鏈上那一列取 K2 / K2_bid。
      runRepairIfReady();
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
        '<p class="mt-2" style="color:#5F5E5A; font-size:20px;">本次範例：S* = $' + fmt(tab.k2) + ' + $' + fmt(tab.s_star - tab.k2) + ' = $' + fmt(tab.s_star) + '</p>' +
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
        '<p class="mt-1" style="color:#5F5E5A; font-size:20px;">本次範例：Y = ($' + fmt(tab.closeout_value) + ' − $' + fmt(tab.cost_per_contract) + ') ÷ $' + fmt(tab.max_profit) + ' = ' + (typeof pct === 'number' ? pct + '%' : '—') + '</p>' +
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
      var payload = { symbol: CFG.symbol, expiration: CFG.expiration, k1: k1, k1_ask: k1Ask };
      if (!isNaN(k1Bid)) payload.k1_bid = k1Bid;
      fetch(CFG.routes.recommend, {
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
      // k2_bid 理論上可以從 tab.debit 與下拉選單的 ask 回推，但最可靠的來源是
      // 這個 K2 實際渲染出來的鏈上那一列，所以直接讀它。
      // （原本這裡先用 tab.k2 - tab.breakeven + k1 算一次，但下面必定覆寫，
      //   算出來的值從來沒被讀過。）
      var k2Row = document.getElementById(strikeRowId(tab.k2));
      var bidAttr = k2Row ? k2Row.getAttribute('data-bid') : null;
      if (bidAttr === null || bidAttr === '') return;
      var k2Bid = parseFloat(bidAttr);

      var payload = { k1: k1, k2: tab.k2, k2_bid: k2Bid, basis: basis };
      var currentBid = parseFloat(currentBidInput ? currentBidInput.value : '');
      if (!isNaN(currentBid)) payload.k1_current_bid = currentBid;
      if (typeof CURRENT_PRICE === 'number') payload.current_price = CURRENT_PRICE;

      fetch(CFG.routes.calculate, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
        body: JSON.stringify(payload)
      })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        renderRepairResult(d);
        if (window.FairPriceTrack) window.FairPriceTrack.command('bcvs_calculate', payload);
      })
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
}
