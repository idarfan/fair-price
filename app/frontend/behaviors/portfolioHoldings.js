/**
 * 投資組合持股列表：即時報價、損益試算、拖曳排序。
 *
 * 稽核 H-3：原本內嵌在 app/components/portfolio/holding_list_component.rb 的 heredoc 裡。
 * 這裡是「逐字搬移」——行為完全不變，只是離開 Ruby 字串、進到 Vite 打包與 ESLint 覆蓋範圍。
 * TODO：型別化成 .ts（strict 模式下這批共約 600 個「可能是 null」與隱含 any 要處理）。
 */

export function init() {
  (function () {
    // ── OCR loading state ─────────────────────────────────────
    var ocrForm = document.querySelector('form[action="/portfolio/ocr_import"]');
    if (ocrForm) {
      ocrForm.addEventListener('submit', function () {
        var btn     = document.getElementById('ocr-submit-btn');
        var loading = document.getElementById('ocr-loading');
        if (btn)     { btn.disabled = true; btn.classList.add('opacity-50'); }
        if (loading) { loading.classList.remove('hidden'); }
      });
    }

    // ── Stock logo fallback ───────────────────────────────────
    document.querySelectorAll('.stock-logo').forEach(function (img) {
      img.addEventListener('error', function () {
        var fb = img.dataset.fallback;
        if (fb && img.src !== fb) {
          img.src = fb;
        } else {
          img.style.display = 'none';
          var span = img.nextElementSibling;
          if (span) span.style.display = 'flex';
        }
      });
    });

    // ── Sortable drag & drop ──────────────────────────────────
    var tbody = document.getElementById('sortable-portfolio');
    if (tbody && typeof Sortable !== 'undefined') {
      Sortable.create(tbody, {
        handle: '.drag-handle',
        animation: 150,
        ghostClass: 'bg-blue-50',
        onEnd: function () {
          var ids = Array.from(tbody.querySelectorAll('tr[data-id]'))
                         .map(function (tr) { return tr.dataset.id; });
          fetch('/portfolio/reorder', {
            method: 'PATCH',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            },
            body: JSON.stringify({ ids: ids })
          });
        }
      });
    }

    // ── Delete confirm ────────────────────────────────────────
    document.addEventListener('click', function (e) {
      var btn = e.target.closest('button[type="submit"]');
      if (!btn) return;
      var msg = btn.closest('form')?.dataset.confirmDelete;
      if (msg && !confirm(msg)) e.preventDefault();
    });

    // ── Live quote polling (every 60 s) ───────────────────────
    function fmtCurrency(v) {
      if (v == null) return '—';
      return '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    function flash(el) {
      el.style.transition = 'background 0.3s';
      el.style.background = '#fef9c3';
      setTimeout(function () { el.style.background = ''; }, 800);
    }
    function applyQuotes(quotes) {
      document.querySelectorAll('tr[data-id]').forEach(function (row) {
        var id        = row.dataset.id;
        var shares    = parseFloat(row.dataset.shares);
        var unitCost  = parseFloat(row.dataset.unitCost);
        var totalCost = unitCost * shares;
        var sym       = row.querySelector('span.font-mono')?.textContent?.trim();
        if (!sym || !quotes[sym]) return;
        var q = quotes[sym];
        var c = q.c, d = q.d, dp = q.dp;

        var priceCell = document.getElementById('cell-price-' + id);
        if (priceCell && c > 0) {
          priceCell.innerHTML = '<span class="font-semibold text-gray-900 text-xs">' + fmtCurrency(c) + '</span>';
          flash(priceCell);
        }
        var dCell = document.getElementById('cell-changed-' + id);
        if (dCell && d != null) {
          var dc = d >= 0 ? 'text-green-600' : 'text-red-600';
          dCell.innerHTML = '<span class="text-xs ' + dc + '">' + (d >= 0 ? '+' : '') + fmtCurrency(d) + '</span>';
          flash(dCell);
        }
        var dpCell = document.getElementById('cell-changedp-' + id);
        if (dpCell && dp != null) {
          var dpc = dp >= 0 ? 'text-green-600' : 'text-red-600';
          dpCell.innerHTML = '<span class="text-xs font-medium ' + dpc + '">' + (dp >= 0 ? '+' : '') + dp.toFixed(2) + '%</span>';
          flash(dpCell);
        }
        var mktCell = document.getElementById('cell-mktval-' + id);
        if (mktCell && c > 0) {
          mktCell.innerHTML = '<span class="text-xs">' + fmtCurrency(c * shares) + '</span>';
          flash(mktCell);
        }
        var pnlCell = document.getElementById('cell-pnl-' + id);
        if (pnlCell && c > 0) {
          var pnl = c * shares - totalCost;
          var pc  = pnl >= 0 ? 'text-green-600' : 'text-red-500';
          pnlCell.innerHTML = '<span class="text-xs ' + pc + '">' + (pnl >= 0 ? '+' : '') + fmtCurrency(pnl) + '</span>';
          flash(pnlCell);
        }
        var pnlPctCell = document.getElementById('cell-pnlpct-' + id);
        if (pnlPctCell && c > 0 && totalCost > 0) {
          var pnlPct = (c * shares - totalCost) / totalCost * 100;
          var ppc    = pnlPct >= 0 ? 'text-green-600' : 'text-red-500';
          pnlPctCell.innerHTML = '<span class="text-xs ' + ppc + '">' + (pnlPct >= 0 ? '+' : '') + pnlPct.toFixed(2) + '%</span>';
          flash(pnlPctCell);
        }
      });
    }
    function pollQuotes() {
      fetch('/portfolio/quotes')
        .then(function (r) { return r.json(); })
        .then(function (data) { applyQuotes(data); })
        .catch(function () {});
    }
    setInterval(pollQuotes, 60000);

    // ── Profit ↔ Sell price bidirectional calculation ─────────
    document.querySelectorAll('input[data-holding-id]').forEach(function (profitInput) {
      var id        = profitInput.dataset.holdingId;
      var unitCost  = parseFloat(profitInput.dataset.unitCost);
      var shares    = parseFloat(profitInput.dataset.shares);
      var sellInput = document.getElementById('sell-price-' + id);
      if (!sellInput || !shares) return;

      profitInput.addEventListener('input', function () {
        var profit = parseFloat(profitInput.value);
        if (!isNaN(profit)) {
          sellInput.value = (unitCost + profit / shares).toFixed(2);
          profitInput.className = profitInput.className.replace(/text-(green|red)-\d+/g, '');
          profitInput.classList.add(profit >= 0 ? 'text-green-600' : 'text-red-500');
        } else {
          sellInput.value = '';
        }
      });

      sellInput.addEventListener('input', function () {
        var sell = parseFloat(sellInput.value);
        if (!isNaN(sell)) {
          var profit = (sell - unitCost) * shares;
          profitInput.value = profit.toFixed(2);
          profitInput.className = profitInput.className.replace(/text-(green|red)-\d+/g, '');
          profitInput.classList.add(profit >= 0 ? 'text-green-600' : 'text-red-500');
        } else {
          profitInput.value = '';
        }
      });
    });
  })();
}
