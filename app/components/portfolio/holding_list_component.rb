# frozen_string_literal: true

class Portfolio::HoldingListComponent < ApplicationComponent
  HEADERS = [
    { label: "",       align: "left",  width: "w-6" },
    { label: "代號",   align: "left"  },
    { label: "股數",   align: "right" },
    { label: "現價",   align: "right" },
    { label: "變更$",  align: "right" },
    { label: "變更%",  align: "right" },
    { label: "市值",   align: "right" },
    { label: "單位成本", align: "right" },
    { label: "成本",   align: "right" },
    { label: "盈虧$",  align: "right" },
    { label: "盈虧%",  align: "right" },
    { label: "賣出價", align: "right" },
    { label: "目標獲利", align: "right" },
    { label: "",       align: "right" }
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
    render_ownership_modal
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
          { id: "pf_symbol",    name: "portfolio[symbol]",    label: "股票代號", type: "text",   placeholder: "AAPL",   extra: { required: true, maxlength: 10 },  cls: "w-24 font-mono uppercase" },
          { id: "pf_shares",    name: "portfolio[shares]",    label: "股數",     type: "number", placeholder: "10",     extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-28" },
          { id: "pf_unit_cost", name: "portfolio[unit_cost]", label: "單位成本", type: "number", placeholder: "150.00", extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-32" },
          { id: "pf_sell",      name: "portfolio[sell_price]", label: "賣出價(選填)", type: "number", placeholder: "—",  extra: { step: "0.01", min: "0" },             cls: "w-28" }
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

      form(
        action:  "/portfolio/ocr_import",
        method:  "post",
        enctype: "multipart/form-data",
        class:   "flex flex-wrap items-end gap-3"
      ) do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "ocr_image") { plain("選擇圖片（PNG / JPG）") }
          input(
            type:   "file",
            id:     "ocr_image",
            name:   "image",
            accept: "image/png,image/jpeg,image/jpg,image/webp",
            required: true,
            class:  "text-sm text-gray-600 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg " \
                    "file:border-0 file:text-xs file:font-medium file:bg-blue-50 " \
                    "file:text-blue-700 hover:file:bg-blue-100 cursor-pointer"
          )
        end

        button(
          type:  "submit",
          id:    "ocr-submit-btn",
          class: "px-4 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-lg " \
                 "hover:bg-indigo-700 transition-colors"
        ) { plain("辨識並匯入") }

        span(
          id:    "ocr-loading",
          class: "hidden text-xs text-indigo-500 animate-pulse"
        ) { plain("🔍 辨識中，請稍候…") }
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
          th(class: "px-2 py-2 #{align_class} text-xs font-semibold text-gray-400 uppercase tracking-wide whitespace-nowrap #{h[:width]}") do
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

  def render_ownership_modal
    # 可拖動浮動面板，初始位置：右側垂直置中
    div(id:    "ownership-panel",
        style: "display:none; position:fixed; left:50%; top:50%; " \
               "transform:translate(-50%,-50%); z-index:50; " \
               "min-width:28rem; width:max-content; max-width:min(56rem,92vw); " \
               "max-height:82vh; overflow-y:auto;",
        class: "bg-white rounded-2xl shadow-2xl border-2 border-orange-200") do
      # 標題列（拖動把手）
      div(id:    "ownership-titlebar",
          class: "flex items-center justify-between px-4 py-3 border-b border-gray-100 " \
                 "cursor-move select-none sticky top-0 bg-white rounded-t-2xl") do
        div(class: "flex items-center gap-2 min-w-0") do
          img(id:    "ownership-logo-img",
              src:   "",
              alt:   "",
              class: "flex-shrink-0 w-6 h-6 rounded-full object-contain border border-gray-100 bg-white")
          span(id:    "ownership-title",
               class: "text-sm font-bold text-gray-900 truncate") { plain("持股結構") }
        end
        button(id:    "ownership-close-btn",
               type:  "button",
               class: "flex-shrink-0 ml-2 text-gray-400 hover:text-gray-600 text-xl leading-none transition-colors") do
          plain("×")
        end
      end

      # 內容區
      div(class: "p-4") do
        div(id: "ownership-loading", style: "display:none",
            class: "py-6 text-center text-sm text-gray-400 animate-pulse") { plain("載入中…") }
        div(id: "ownership-error", style: "display:none",
            class: "py-4 text-center text-sm text-red-400")
        div(id: "ownership-body", style: "display:none", class: "space-y-4") do
          # summary 卡片
          div(id: "ownership-summary", class: "grid grid-cols-2 gap-2")
          # top holders 表格
          div do
            p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2") { plain("主要機構持有人") }
            div(class: "overflow-x-auto") do
              table(class: "w-full text-xs") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-2 py-1.5 text-left text-gray-400 font-semibold") { plain("機構") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("持股 %") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("市值") }
                    th(class: "px-2 py-1.5 text-right text-gray-400 font-semibold") { plain("申報日") }
                  end
                end
                tbody(id: "ownership-holders-body")
              end
            end
          end
        end
      end
    end
  end

  def render_script
    script do
      raw <<~JS.html_safe
        (function () {
          // ── OCR loading state ─────────────────────────────────────
          var ocrForm = document.querySelector('form[action="/portfolio/ocr_import"]');
          if (ocrForm) {
            ocrForm.addEventListener('submit', function() {
              var btn     = document.getElementById('ocr-submit-btn');
              var loading = document.getElementById('ocr-loading');
              if (btn)     { btn.disabled = true; btn.classList.add('opacity-50'); }
              if (loading) { loading.classList.remove('hidden'); }
            });
          }

          // ── Stock logo fallback ───────────────────────────────────
          document.querySelectorAll('.stock-logo').forEach(function(img) {
            img.addEventListener('error', function() {
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
              onEnd: function() {
                var ids = Array.from(tbody.querySelectorAll('tr[data-id]'))
                               .map(function(tr) { return tr.dataset.id; });
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
          document.addEventListener('click', function(e) {
            var btn = e.target.closest('button[type="submit"]');
            if (!btn) return;
            var msg = btn.closest('form')?.dataset.confirmDelete;
            if (msg && !confirm(msg)) e.preventDefault();
          });

          // ── Live quote polling (every 60 s, no page reload) ──────
          function fmtCurrency(v) {
            if (v == null) return '—';
            return '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
          }
          function flash(el) {
            el.style.transition = 'background 0.3s';
            el.style.background = '#fef9c3';
            setTimeout(function() { el.style.background = ''; }, 800);
          }
          function applyQuotes(quotes) {
            document.querySelectorAll('tr[data-id]').forEach(function(row) {
              var id        = row.dataset.id;
              var shares    = parseFloat(row.dataset.shares);
              var unitCost  = parseFloat(row.dataset.unitCost);
              var totalCost = unitCost * shares;
              var sym       = row.querySelector('span.font-mono')?.textContent?.trim();
              if (!sym || !quotes[sym]) return;
              var q  = quotes[sym];
              var c  = q.c,  d = q.d,  dp = q.dp;

              // price
              var priceCell = document.getElementById('cell-price-' + id);
              if (priceCell && c > 0) {
                priceCell.innerHTML = '<span class="font-semibold text-gray-900 text-xs">' + fmtCurrency(c) + '</span>';
                flash(priceCell);
              }
              // change $
              var dCell = document.getElementById('cell-changed-' + id);
              if (dCell && d != null) {
                var dc = d >= 0 ? 'text-green-600' : 'text-red-600';
                dCell.innerHTML = '<span class="text-xs ' + dc + '">' + (d >= 0 ? '+' : '') + fmtCurrency(d) + '</span>';
                flash(dCell);
              }
              // change %
              var dpCell = document.getElementById('cell-changedp-' + id);
              if (dpCell && dp != null) {
                var dpc = dp >= 0 ? 'text-green-600' : 'text-red-600';
                dpCell.innerHTML = '<span class="text-xs font-medium ' + dpc + '">' + (dp >= 0 ? '+' : '') + dp.toFixed(2) + '%</span>';
                flash(dpCell);
              }
              // market value
              var mktCell = document.getElementById('cell-mktval-' + id);
              if (mktCell && c > 0) {
                mktCell.innerHTML = '<span class="text-xs">' + fmtCurrency(c * shares) + '</span>';
                flash(mktCell);
              }
              // pnl $
              var pnlCell = document.getElementById('cell-pnl-' + id);
              if (pnlCell && c > 0) {
                var pnl = c * shares - totalCost;
                var pc  = pnl >= 0 ? 'text-green-600' : 'text-red-500';
                pnlCell.innerHTML = '<span class="text-xs ' + pc + '">' + (pnl >= 0 ? '+' : '') + fmtCurrency(pnl) + '</span>';
                flash(pnlCell);
              }
              // pnl %
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
              .then(function(r) { return r.json(); })
              .then(function(data) { applyQuotes(data); })
              .catch(function() {}); // silently ignore errors
          }
          setInterval(pollQuotes, 60000); // every 60 seconds

          // ── Profit ↔ Sell price bidirectional calculation ─────────
          document.querySelectorAll('input[data-holding-id]').forEach(function(profitInput) {
            var id        = profitInput.dataset.holdingId;
            var unitCost  = parseFloat(profitInput.dataset.unitCost);
            var shares    = parseFloat(profitInput.dataset.shares);
            var sellInput = document.getElementById('sell-price-' + id);
            if (!sellInput || !shares) return;

            profitInput.addEventListener('input', function() {
              var profit = parseFloat(profitInput.value);
              if (!isNaN(profit)) {
                sellInput.value = (unitCost + profit / shares).toFixed(2);
                profitInput.className = profitInput.className.replace(/text-(green|red)-\d+/g, '');
                profitInput.classList.add(profit >= 0 ? 'text-green-600' : 'text-red-500');
              } else {
                sellInput.value = '';
              }
            });

            sellInput.addEventListener('input', function() {
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
          // ── Ownership panel (draggable, right-side) ───────────────
          var ownershipPanel    = document.getElementById('ownership-panel');
          var ownershipTitlebar = document.getElementById('ownership-titlebar');
          var ownershipLoading  = document.getElementById('ownership-loading');
          var ownershipError    = document.getElementById('ownership-error');
          var ownershipBody     = document.getElementById('ownership-body');
          var ownershipTitle    = document.getElementById('ownership-title');
          var ownershipLogoImg  = document.getElementById('ownership-logo-img');

          // ── Drag ─────────────────────────────────────────────────
          var isDragging = false, dragOffX = 0, dragOffY = 0;

          ownershipTitlebar.addEventListener('mousedown', function(e) {
            if (e.target.id === 'ownership-close-btn') return;
            isDragging = true;
            var rect = ownershipPanel.getBoundingClientRect();
            ownershipPanel.style.transform = 'none';
            ownershipPanel.style.top   = rect.top + 'px';
            ownershipPanel.style.left  = rect.left + 'px';
            ownershipPanel.style.right = 'auto';
            dragOffX = e.clientX - rect.left;
            dragOffY = e.clientY - rect.top;
            e.preventDefault();
          });
          document.addEventListener('mousemove', function(e) {
            if (!isDragging) return;
            ownershipPanel.style.left = (e.clientX - dragOffX) + 'px';
            ownershipPanel.style.top  = (e.clientY - dragOffY) + 'px';
          });
          document.addEventListener('mouseup', function() { isDragging = false; });

          // ── Open / Close ──────────────────────────────────────────
          function openOwnershipPanel(symbol) {
            // 重置至初始位置（螢幕正中央）
            ownershipPanel.style.left      = '50%';
            ownershipPanel.style.right     = 'auto';
            ownershipPanel.style.top       = '50%';
            ownershipPanel.style.transform = 'translate(-50%, -50%)';

            ownershipTitle.textContent     = symbol + ' 持股結構';
            ownershipLogoImg.src           = 'https://assets.parqet.com/logos/symbol/' + symbol + '?format=jpg';
            ownershipLogoImg.alt           = symbol;
            ownershipLoading.style.display = 'block';
            ownershipError.style.display   = 'none';
            ownershipBody.style.display    = 'none';
            ownershipPanel.style.display   = 'block';

            fetch('/portfolio/ownership?symbol=' + encodeURIComponent(symbol))
              .then(function(r) { return r.json(); })
              .then(function(data) {
                ownershipLoading.style.display = 'none';
                if (data.error || (!data.summary && (!data.top_holders || data.top_holders.length === 0))) {
                  ownershipError.textContent   = '無法取得持股資料，請稍後再試';
                  ownershipError.style.display = 'block';
                  return;
                }
                renderOwnershipData(data, symbol);
                ownershipBody.style.display = 'block';
              })
              .catch(function() {
                ownershipLoading.style.display = 'none';
                ownershipError.textContent     = '載入失敗，請檢查網路連線';
                ownershipError.style.display   = 'block';
              });
          }

          function closeOwnershipPanel() {
            ownershipPanel.style.display = 'none';
          }

          // ── Render ────────────────────────────────────────────────
          var SHORT_TOOLTIP = '持股比例超過 100%，通常因放空借券導致同一股票被重複計入，屬正常市場現象';

          function fmtPct(val) {
            if (val == null) return '—';
            var pct = val * 100;
            var str = pct.toFixed(2) + '%';
            if (pct > 100) {
              str += ' <span title="' + SHORT_TOOLTIP + '" style="cursor:help">⚠️</span>';
            }
            return str;
          }
          function fmtBillion(val) {
            if (val == null) return '—';
            if (val >= 1e9) return '$' + (val / 1e9).toFixed(2) + 'B';
            if (val >= 1e6) return '$' + (val / 1e6).toFixed(2) + 'M';
            return '$' + val.toLocaleString('en-US');
          }

          function renderOwnershipData(data, symbol) {
            var sourceLabel = data.source ? ' · 來源：' + data.source : '';
            ownershipTitle.textContent = symbol + ' 持股結構' + sourceLabel;

            var summaryEl = document.getElementById('ownership-summary');
            summaryEl.innerHTML = '';
            var cards = data.summary ? [
              { label: '機構持股（佔總股本）',      val: data.summary.institutions_pct },
              { label: '內部人持股（佔總股本）',    val: data.summary.insiders_pct },
              { label: '機構持有 Float（佔流通股）', val: data.summary.institutions_float_pct },
              { label: '機構總數', raw: data.summary.institutions_count != null ? data.summary.institutions_count.toLocaleString() : '—' }
            ] : [];
            cards.forEach(function(c) {
              var display = c.raw !== undefined ? c.raw : fmtPct(c.val);
              var d = document.createElement('div');
              d.className = 'bg-gray-50 rounded-lg px-3 py-2';
              d.innerHTML = '<p class="text-xs text-gray-400 mb-0.5">' + c.label + '</p>' +
                            '<p class="text-sm font-bold text-gray-800">' + display + '</p>';
              summaryEl.appendChild(d);
            });

            var tbody = document.getElementById('ownership-holders-body');
            tbody.innerHTML = '';
            if (!data.top_holders || data.top_holders.length === 0) {
              var tr = document.createElement('tr');
              tr.innerHTML = '<td colspan="4" class="px-2 py-4 text-center text-gray-300">無資料</td>';
              tbody.appendChild(tr);
              return;
            }
            data.top_holders.forEach(function(h) {
              var tr = document.createElement('tr');
              tr.className = 'border-t border-gray-50';
              tr.innerHTML =
                '<td class="px-2 py-1.5 text-gray-700 max-w-xs truncate" title="' + h.name + '">' + h.name + '</td>' +
                '<td class="px-2 py-1.5 text-right font-mono text-gray-700">' + fmtPct(h.pct_held) + '</td>' +
                '<td class="px-2 py-1.5 text-right text-gray-500">' + fmtBillion(h.value) + '</td>' +
                '<td class="px-2 py-1.5 text-right text-gray-400">' + (h.report_date || '—') + '</td>';
              tbody.appendChild(tr);
            });
          }

          // 點擊 symbol cell 開啟面板
          document.addEventListener('click', function(e) {
            var cell = e.target.closest('td[data-ownership-symbol]');
            if (!cell) return;
            openOwnershipPanel(cell.dataset.ownershipSymbol);
          });

          // 關閉事件
          document.getElementById('ownership-close-btn').addEventListener('click', closeOwnershipPanel);
          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') closeOwnershipPanel();
          });
        })();
      JS
    end
  end
end
