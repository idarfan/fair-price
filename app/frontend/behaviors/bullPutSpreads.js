/**
 * Bull Put Spread 頁：到期日/期權鏈抓取、輪詢、波動率、試算。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_put_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 * 與 Bull Call 共用的小工具已抽到 shared/spreadHelpers.js（稽核 M-6）。
 * TODO：型別化成 .ts。
 */

import { createSpreadHelpers } from "./shared/spreadHelpers";

export function init(root) {
  var CFG = JSON.parse(root.dataset.config);

  (function () {
    var H = createSpreadHelpers({ prefix: 'bpus', statusPath: CFG.routes.status });
    var csrf = H.csrf, pollJob = H.pollJob, showProgress = H.showProgress;
    var fmt = H.fmt, fmtLots = H.fmtLots, currentLots = H.currentLots;

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
          pollJob(d.job_id, function (status) {
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

    var retryBtn = document.getElementById('bpus-fetch-expirations-btn');
    if (retryBtn) {
      retryBtn.addEventListener('click', function () {
        fetchExpirations(CFG.symbol);
      });
    }

    // ── Step2: 點履約日 → 抓 Put 鏈 ──────────────────────────────────────
    document.querySelectorAll('[data-bpus-expiration-btn]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var exp = btn.getAttribute('data-exp');
        var symbol = CFG.symbol;
        showProgress();
        document.querySelectorAll('[data-bpus-expiration-btn]').forEach(function (b) { b.disabled = true; });
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
            pollJob(d.job_id, function (status) { window.location.href = base + '&chain_job_status=' + status; });
          } else {
            window.location.href = base + '&chain_job_status=error';
          }
        }).catch(function () {
          window.location.href = CFG.routes.index + '?symbol=' + symbol + '&expiration=' + encodeURIComponent(exp) + '&chain_job_status=error';
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
      fetch(CFG.routes.volatility + '?symbol=' + encodeURIComponent(symbol) + '&expiration=' + encodeURIComponent(expiration))
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

    if (document.getElementById('bpus-chain-table') && CFG.expiration) {
      fetchVolatility(CFG.symbol, CFG.expiration);
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

    // 口數：金額類結果用「單口 × 口數 = 總計」呈現；BE/ROC/風險報酬比是
    // 比率，不隨口數變化，維持單口顯示(bpus-fix.md 項目5)。
    var lastCalcResult = null;

    function runCalculate() {
      var payload = {
        short_strike: state.csp.strike, short_bid: state.csp.bid,
        long_strike: state.protection.strike, long_ask: state.protection.ask
      };
      fetch(CFG.routes.calculate, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
        body: JSON.stringify(payload)
      })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        lastCalcResult = d;
        renderCalcResult(d);
        if (window.FairPriceTrack) window.FairPriceTrack.command('bpus_calculate', payload);
      })
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
        '<div><dt class="text-[24px] text-gray-500">淨權利金收入</dt><dd class="font-semibold">' + fmtLots(d.net_credit, lots) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">價差寬度</dt><dd class="font-semibold">' + fmt(d.width) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">' + fmtLots(d.max_profit, lots) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">最大虧損</dt><dd class="font-semibold text-red-700">' + fmtLots(d.max_loss, lots) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">押金</dt><dd class="font-semibold text-red-700">' + fmtLots(d.margin, lots) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">損益平衡點</dt><dd class="font-semibold">$' + fmt(d.breakeven) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">ROC</dt><dd class="font-semibold text-yellow-700">' + (d.roc === null ? '—' : d.roc + '%') + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">風險報酬比</dt><dd class="font-semibold">' + (d.risk_reward === null ? '—' : '1 : ' + d.risk_reward) + '</dd></div>' +
        '<div><dt class="text-[24px] text-gray-500">提前指派：承接現金</dt><dd class="font-semibold text-purple-700">' + assignCashHtml + '</dd></div>';

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
}
