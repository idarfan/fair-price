# frozen_string_literal: true

class StockAlert::AlertListComponent < ApplicationComponent
  # @param alerts      [ActiveRecord::Relation] PriceAlert records ordered by position
  # @param market_data [Hash] symbol => Finnhub quote hash { "c" => price, ... }
  def initialize(alerts:, market_data: {})
    @alerts      = alerts
    @market_data = market_data
  end

  def view_template # rubocop:disable Metrics/MethodLength
    div(class: "space-y-5") do
      render_header
      render_add_form
      if @alerts.any?
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
    div(class: "flex items-center justify-between") do
      div do
        h1(class: "text-xl font-bold text-gray-900") do
          span(class: "mr-2") { plain("🔔") }
          plain("到價通知")
        end
        p(class: "text-sm text-gray-400 mt-0.5") { plain("設定目標價，達標時自動發送 Telegram 通知") }
      end
    end
  end

  def render_add_form
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      h2(class: "text-sm font-semibold text-gray-600 mb-3") { plain("新增通知") }
      form(
        action: watchlist_alerts_path,
        method: "post",
        class: "flex flex-wrap gap-2 items-end"
      ) do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "pa_symbol") { plain("股票代號") }
          input(
            type: "text", id: "pa_symbol", name: "price_alert[symbol]",
            placeholder: "AAPL", required: true,
            class: "w-24 px-2 py-1.5 text-sm border border-gray-200 rounded-lg font-mono uppercase focus:outline-none focus:ring-2 focus:ring-blue-300"
          )
        end

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "pa_target") { plain("目標價 ($)") }
          input(
            type: "number", id: "pa_target", name: "price_alert[target_price]",
            placeholder: "150.00", step: "0.01", min: "0.01", required: true,
            class: "w-32 px-2 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-300"
          )
        end

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "pa_condition") { plain("條件") }
          select(
            id: "pa_condition", name: "price_alert[condition]",
            class: "px-2 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-300"
          ) do
            option(value: "above") { plain("高於 ▲") }
            option(value: "below") { plain("低於 ▼") }
          end
        end

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "pa_notes") { plain("備註（選填）") }
          input(
            type: "text", id: "pa_notes", name: "price_alert[notes]",
            placeholder: "備忘事項…",
            class: "w-40 px-2 py-1.5 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-300"
          )
        end

        button(
          type: "submit",
          class: "px-4 py-1.5 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
        ) { plain("新增") }
      end
    end
  end

  def render_table
    div(
      id: "alerts-table",
      class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden"
    ) do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          render_table_header
          tbody(id: "sortable-alerts") do
            @alerts.each do |alert|
              render StockAlert::AlertRowComponent.new(
                alert:       alert,
                market_data: @market_data
              )
            end
          end
        end
      end
    end
  end

  def render_table_header
    thead(class: "bg-gray-50 border-b border-gray-100") do
      tr do
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide w-8") { plain("") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("代號") }
        th(class: "px-3 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("現價") }
        th(class: "px-3 py-2.5 text-center text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("條件") }
        th(class: "px-3 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("目標價") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("備註") }
        th(class: "px-3 py-2.5 text-center text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("狀態") }
        th(class: "px-3 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("操作") }
      end
    end
  end

  def render_empty_state
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm px-5 py-12 text-center") do
      span(class: "text-3xl block mb-3") { plain("🔔") }
      p(class: "text-gray-400 text-sm") { plain("尚無到價通知，請使用上方表單新增") }
    end
  end

  def render_ownership_modal # rubocop:disable Metrics/MethodLength
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
               class: "flex-shrink-0 ml-2 text-gray-400 hover:text-gray-600 text-xl leading-none transition-colors") do
          plain("×")
        end
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

  def render_script # rubocop:disable Metrics/MethodLength
    script do
      raw <<~'JS'.html_safe
        (function () {
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
          var tbody = document.getElementById('sortable-alerts');
          if (tbody && typeof Sortable !== 'undefined') {
            Sortable.create(tbody, {
              handle: '.drag-handle',
              animation: 150,
              onEnd: function () {
                var ids = Array.from(tbody.querySelectorAll('tr[data-alert-id]'))
                              .map(function (r) { return r.dataset.alertId; });
                fetch('/watchlist/reorder', {
                  method: 'PATCH',
                  headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
                  body: JSON.stringify({ ids: ids })
                });
              }
            });
          }

          // ── Ownership panel (draggable) ───────────────────────────
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

            var holdersBody = document.getElementById('ownership-holders-body');
            holdersBody.innerHTML = '';
            if (!data.top_holders || data.top_holders.length === 0) {
              var tr = document.createElement('tr');
              tr.innerHTML = '<td colspan="4" class="px-2 py-4 text-center text-gray-300">無資料</td>';
              holdersBody.appendChild(tr);
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
              holdersBody.appendChild(tr);
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
