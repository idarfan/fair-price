# frozen_string_literal: true

# Shared draggable ownership breakdown panel.
# Renders the HTML modal + all ownership-related JavaScript.
# Trigger by clicking any element with `data-ownership-symbol="AAPL"`.
# Used by HoldingListComponent and AlertListComponent.
class Shared::OwnershipPanelComponent < ApplicationComponent
  def view_template
    render_panel
    render_script
  end

  private

  def render_panel
    div(id:    "ownership-panel",
        style: "display:none; position:fixed; left:50%; top:50%; " \
               "transform:translate(-50%,-50%); z-index:50; " \
               "min-width:28rem; width:max-content; max-width:min(56rem,92vw); " \
               "max-height:82vh; overflow-y:auto;",
        class: "bg-white rounded-2xl shadow-2xl border-2 border-orange-200") do
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
               class: "flex-shrink-0 ml-2 text-gray-400 hover:text-gray-600 text-xl " \
                      "leading-none transition-colors") { plain("×") }
      end

      div(class: "p-4") do
        div(id: "ownership-loading", style: "display:none",
            class: "py-6 text-center text-sm text-gray-400 animate-pulse") { plain("載入中…") }
        div(id: "ownership-error", style: "display:none",
            class: "py-4 text-center text-sm text-red-400")
        div(id: "ownership-body", style: "display:none", class: "space-y-4") do
          div(id: "ownership-summary", class: "grid grid-cols-2 gap-2")
          div do
            p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2") { plain("主要機構持有人") }
            div(class: "overflow-x-auto") do
              table(class: "w-full text-xs") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-2 py-1.5 text-left text-gray-400 font-semibold")  { plain("機構") }
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
      raw <<~'JS'.html_safe
        (function () {
          var ownershipPanel    = document.getElementById('ownership-panel');
          var ownershipTitlebar = document.getElementById('ownership-titlebar');
          var ownershipLoading  = document.getElementById('ownership-loading');
          var ownershipError    = document.getElementById('ownership-error');
          var ownershipBody     = document.getElementById('ownership-body');
          var ownershipTitle    = document.getElementById('ownership-title');
          var ownershipLogoImg  = document.getElementById('ownership-logo-img');

          // ── Drag ───────────────────────────────────────────────────
          var isDragging = false, dragOffX = 0, dragOffY = 0;

          ownershipTitlebar.addEventListener('mousedown', function (e) {
            if (e.target.id === 'ownership-close-btn') return;
            isDragging = true;
            var rect = ownershipPanel.getBoundingClientRect();
            ownershipPanel.style.transform = 'none';
            ownershipPanel.style.top   = rect.top  + 'px';
            ownershipPanel.style.left  = rect.left + 'px';
            ownershipPanel.style.right = 'auto';
            dragOffX = e.clientX - rect.left;
            dragOffY = e.clientY - rect.top;
            e.preventDefault();
          });
          document.addEventListener('mousemove', function (e) {
            if (!isDragging) return;
            ownershipPanel.style.left = (e.clientX - dragOffX) + 'px';
            ownershipPanel.style.top  = (e.clientY - dragOffY) + 'px';
          });
          document.addEventListener('mouseup', function () { isDragging = false; });

          // ── Open / Close ────────────────────────────────────────────
          function openOwnershipPanel(symbol) {
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
              .then(function (r) { return r.json(); })
              .then(function (data) {
                ownershipLoading.style.display = 'none';
                if (data.error || (!data.summary && (!data.top_holders || data.top_holders.length === 0))) {
                  ownershipError.textContent   = '無法取得持股資料，請稍後再試';
                  ownershipError.style.display = 'block';
                  return;
                }
                renderOwnershipData(data, symbol);
                ownershipBody.style.display = 'block';
              })
              .catch(function () {
                ownershipLoading.style.display = 'none';
                ownershipError.textContent     = '載入失敗，請檢查網路連線';
                ownershipError.style.display   = 'block';
              });
          }

          function closeOwnershipPanel() {
            ownershipPanel.style.display = 'none';
          }

          // ── Render data ─────────────────────────────────────────────
          var SHORT_TOOLTIP = '持股比例超過 100%，通常因放空借券導致同一股票被重複計入，屬正常市場現象';

          function fmtPct(val) {
            if (val == null) return '—';
            var pct = val * 100;
            var str = pct.toFixed(2) + '%';
            if (pct > 100) str += ' <span title="' + SHORT_TOOLTIP + '" style="cursor:help">⚠️</span>';
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
              { label: '機構持股（佔總股本）',       val: data.summary.institutions_pct },
              { label: '內部人持股（佔總股本）',     val: data.summary.insiders_pct },
              { label: '機構持有 Float（佔流通股）', val: data.summary.institutions_float_pct },
              { label: '機構總數', raw: data.summary.institutions_count != null
                                      ? data.summary.institutions_count.toLocaleString() : '—' }
            ] : [];
            cards.forEach(function (c) {
              var display = c.raw !== undefined ? c.raw : fmtPct(c.val);
              var d = document.createElement('div');
              d.className = 'bg-gray-50 rounded-lg px-3 py-2';
              d.innerHTML = '<p class="text-xs text-gray-400 mb-0.5">' + c.label + '</p>' +
                            '<p class="text-sm font-bold text-gray-800">' + display + '</p>';
              summaryEl.appendChild(d);
            });

            var holdersBody = document.getElementById('ownership-holders-body');
            holdersBody.innerHTML = '';
            if (!data.top_holders || data.top_holders.length === 0) {
              var tr = document.createElement('tr');
              tr.innerHTML = '<td colspan="4" class="px-2 py-4 text-center text-gray-300">無資料</td>';
              holdersBody.appendChild(tr);
              return;
            }
            data.top_holders.forEach(function (h) {
              var tr = document.createElement('tr');
              tr.className = 'border-t border-gray-50';
              tr.innerHTML =
                '<td class="px-2 py-1.5 text-gray-700 max-w-xs truncate" title="' + h.name + '">' + h.name + '</td>' +
                '<td class="px-2 py-1.5 text-right font-mono text-gray-700">'     + fmtPct(h.pct_held) + '</td>' +
                '<td class="px-2 py-1.5 text-right text-gray-500">'               + fmtBillion(h.value) + '</td>' +
                '<td class="px-2 py-1.5 text-right text-gray-400">'               + (h.report_date || '—') + '</td>';
              holdersBody.appendChild(tr);
            });
          }

          // ── Event wiring ─────────────────────────────────────────────
          document.addEventListener('click', function (e) {
            var cell = e.target.closest('[data-ownership-symbol]');
            if (!cell) return;
            openOwnershipPanel(cell.dataset.ownershipSymbol);
          });

          document.getElementById('ownership-close-btn').addEventListener('click', closeOwnershipPanel);
          document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') closeOwnershipPanel();
          });
        })();
      JS
    end
  end
end
