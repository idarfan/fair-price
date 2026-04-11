# frozen_string_literal: true

class DailyMomentum::WatchlistManagerComponent < ApplicationComponent
  # @param items  [Array<WatchlistItem>]  AR records (ordered)
  # @param stocks [Array<Hash>]           Live quote data from MomentumReportService
  def initialize(items:, stocks:)
    @items  = items
    @stocks = stocks
  end

  def view_template
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      if @items.empty?
        render_empty_state
      else
        render_table
      end
    end
    render_scripts
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100 flex items-center justify-between") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("📋") }
        plain("觀察名單")
      end
      span(class: "text-xs text-gray-400 flex items-center gap-1") do
        span { plain("⠿") }
        plain("拖曳可調整順序")
      end
    end
  end

  def render_empty_state
    div(class: "px-5 py-8 text-center text-gray-400 text-sm") do
      plain("觀察名單為空，請使用上方搜尋框加入股票")
    end
  end

  def render_table
    div(class: "overflow-x-auto") do
      table(class: "w-full text-sm") do
        render_thead
        tbody(id: "watchlist-sortable") do
          @items.each do |item|
            stock = @stocks.find { |s| s[:symbol] == item.symbol }
            render DailyMomentum::WatchlistManagerRowComponent.new(item: item, stock: stock)
          end
        end
      end
    end
  end

  def render_thead
    thead(class: "bg-gray-50") do
      tr do
        th(class: "px-2 py-2.5 w-8")
        th(class: "px-4 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("股票") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("現價") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("漲跌") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide hidden md:table-cell") { plain("成交量") }
        th(class: "px-4 py-2.5 text-xs font-semibold text-gray-400 uppercase tracking-wide hidden md:table-cell") { plain("價格區間") }
        th(class: "px-2 py-2.5 w-16")
      end
    end
  end

  def render_scripts
    script do
      raw <<~JS.html_safe
        (function() {
          // ── Stock logo fallback ───────────────────────────────────
          document.querySelectorAll('.stock-logo').forEach(function(img) {
            img.addEventListener('error', function() {
              var fallbackSrc = img.dataset.fallback;
              if (fallbackSrc && img.src !== fallbackSrc) {
                img.src = fallbackSrc;
              } else {
                img.style.display = 'none';
                var span = img.nextElementSibling;
                if (span) span.style.display = 'flex';
              }
            });
          });

          // ── Sortable drag & drop ──────────────────────────────────────
          var el = document.getElementById('watchlist-sortable');
          if (el && typeof Sortable !== 'undefined') {
            Sortable.create(el, {
              handle: '.drag-handle',
              animation: 150,
              ghostClass: 'bg-blue-50',
              onEnd: function() {
                var ids = Array.from(el.querySelectorAll('tr[data-id]')).map(function(tr) {
                  return tr.dataset.id;
                });
                fetch('/momentum/watchlist/reorder', {
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

          // ── Edit / Cancel via event delegation ───────────────────────
          document.addEventListener('click', function(e) {
            var startBtn = e.target.closest('[data-start-edit]');
            if (startBtn) {
              var id = startBtn.dataset.startEdit;
              document.getElementById('view-' + id).classList.add('hidden');
              var form = document.getElementById('edit-form-' + id);
              form.classList.remove('hidden');
              var inp = form.querySelector('input[name="symbol"]');
              inp.focus(); inp.select();
              return;
            }

            var cancelBtn = e.target.closest('[data-cancel-edit]');
            if (cancelBtn) {
              var id = cancelBtn.dataset.cancelEdit;
              document.getElementById('view-' + id).classList.remove('hidden');
              document.getElementById('edit-form-' + id).classList.add('hidden');
              return;
            }

            // Delete confirm
            var delBtn = e.target.closest('button[data-confirm]');
            if (delBtn) {
              e.preventDefault();
              if (confirm(delBtn.dataset.confirm)) {
                delBtn.disabled = true;
                delBtn.style.opacity = '0.4';
                delBtn.closest('form').submit();
              }
            }
          });
        })();
      JS
    end
  end
end
