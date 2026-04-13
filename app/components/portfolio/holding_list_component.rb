# frozen_string_literal: true

class Portfolio::HoldingListComponent < ApplicationComponent
  HEADERS = [
    { label: "",         align: "left",  width: "w-6" },
    { label: "代號",     align: "left"  },
    { label: "股數",     align: "right" },
    { label: "現價",     align: "right" },
    { label: "變更$",    align: "right" },
    { label: "變更%",    align: "right" },
    { label: "市值",     align: "right" },
    { label: "單位成本", align: "right" },
    { label: "成本",     align: "right" },
    { label: "盈虧$",    align: "right" },
    { label: "盈虧%",    align: "right" },
    { label: "賣出價",   align: "right" },
    { label: "目標獲利", align: "right" },
    { label: "",         align: "right" }
  ].freeze

  def initialize(holdings:, quotes: {})
    @holdings = holdings
    @quotes   = quotes
  end

  def view_template
    div(class: "space-y-5") do
      render_header
      render_add_form
      render_ocr_import
      if @holdings.any?
        render_table
      else
        render_empty_state
      end
    end
    render Shared::OwnershipPanelComponent.new
    render_script
  end

  private

  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") do
        span(class: "mr-2") { plain("📁") }
        plain("個人持股追蹤")
      end
      p(class: "text-sm text-gray-400 mt-0.5") { plain("追蹤持倉市值、損益與目標出場價") }
    end
  end

  def render_add_form
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      h2(class: "text-sm font-semibold text-gray-600 mb-3") { plain("新增持股") }
      form(action: "/portfolio", method: "post",
           class: "flex flex-wrap gap-2 items-end") do
        input(type: "hidden", name: "authenticity_token",
              value: helpers.form_authenticity_token)

        [
          { id: "pf_symbol",    name: "portfolio[symbol]",     label: "股票代號",    type: "text",   placeholder: "AAPL",   extra: { required: true, maxlength: 10 }, cls: "w-24 font-mono uppercase" },
          { id: "pf_shares",    name: "portfolio[shares]",     label: "股數",        type: "number", placeholder: "10",     extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-28" },
          { id: "pf_unit_cost", name: "portfolio[unit_cost]",  label: "單位成本",    type: "number", placeholder: "150.00", extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-32" },
          { id: "pf_sell",      name: "portfolio[sell_price]", label: "賣出價(選填)", type: "number", placeholder: "—",      extra: { step: "0.01", min: "0" }, cls: "w-28" }
        ].each do |f|
          div(class: "flex flex-col gap-1") do
            label(class: "text-xs text-gray-400", for: f[:id]) { plain(f[:label]) }
            input(
              type:        f[:type],
              id:          f[:id],
              name:        f[:name],
              placeholder: f[:placeholder],
              class:       "#{f[:cls]} px-2 py-1.5 text-sm border border-gray-200 rounded-lg " \
                           "focus:outline-none focus:ring-2 focus:ring-blue-300",
              **f[:extra]
            )
          end
        end

        button(type: "submit",
               class: "px-4 py-1.5 bg-blue-600 text-white text-sm font-medium rounded-lg " \
                      "hover:bg-blue-700 transition-colors") { plain("新增") }
      end
    end
  end

  def render_ocr_import
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      h2(class: "text-sm font-semibold text-gray-600 mb-1") do
        span(class: "mr-1") { plain("🖼️") }
        plain("圖片匯入（OCR）")
      end
      p(class: "text-xs text-gray-400 mb-3") { plain("上傳持股截圖，自動辨識代號、股數、單位成本並覆寫現有資料") }

      form(action: "/portfolio/ocr_import", method: "post",
           enctype: "multipart/form-data", class: "flex flex-wrap items-end gap-3") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "ocr_image") { plain("選擇圖片（PNG / JPG）") }
          input(
            type: "file", id: "ocr_image", name: "image",
            accept: "image/png,image/jpeg,image/jpg,image/webp", required: true,
            class: "text-sm text-gray-600 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg " \
                   "file:border-0 file:text-xs file:font-medium file:bg-blue-50 " \
                   "file:text-blue-700 hover:file:bg-blue-100 cursor-pointer"
          )
        end

        button(type: "submit", id: "ocr-submit-btn",
               class: "px-4 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-lg " \
                      "hover:bg-indigo-700 transition-colors") { plain("辨識並匯入") }

        span(id: "ocr-loading", class: "hidden text-xs text-indigo-500 animate-pulse") do
          plain("🔍 辨識中，請稍候…")
        end
      end

      div(class: "mt-2 flex items-center gap-1.5 text-xs text-amber-600 bg-amber-50 px-3 py-2 rounded-lg") do
        plain("⚠️ 匯入將覆寫現有所有持股資料，請確認後再操作。")
      end
    end
  end

  def render_table
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          render_thead
          tbody(id: "sortable-portfolio") do
            @holdings.each do |holding|
              render Portfolio::HoldingRowComponent.new(
                holding: holding,
                quote:   @quotes[holding.symbol]
              )
            end
          end
        end
      end
    end
  end

  def render_thead
    thead(class: "bg-gray-50 border-b border-gray-100") do
      tr do
        HEADERS.each do |h|
          align_class = h[:align] == "right" ? "text-right" : "text-left"
          th(class: "px-2 py-2 #{align_class} text-xs font-semibold text-gray-400 uppercase " \
                    "tracking-wide whitespace-nowrap #{h[:width]}") do
            plain(h[:label])
          end
        end
      end
    end
  end

  def render_empty_state
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm px-5 py-12 text-center") do
      span(class: "text-3xl block mb-3") { plain("📁") }
      p(class: "text-gray-400 text-sm") { plain("尚無持股，請使用上方表單新增") }
    end
  end

  def render_script
    script do
      raw <<~JS.html_safe
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
                profitInput.className = profitInput.className.replace(/text-(green|red)-\\d+/g, '');
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
                profitInput.className = profitInput.className.replace(/text-(green|red)-\\d+/g, '');
                profitInput.classList.add(profit >= 0 ? 'text-green-600' : 'text-red-500');
              } else {
                profitInput.value = '';
              }
            });
          });
        })();
      JS
    end
  end
end
