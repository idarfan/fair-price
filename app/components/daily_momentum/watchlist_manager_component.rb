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
            render_row(item, stock)
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

  def render_row(item, stock)
    tr(
      id:    "wl-row-#{item.id}",
      data:  { id: item.id },
      class: "border-t border-gray-100 hover:bg-gray-50 transition-colors group"
    ) do
      td(class: "px-2 py-3 text-center") do
        span(class: "drag-handle cursor-grab active:cursor-grabbing text-gray-300 " \
                    "hover:text-gray-500 select-none text-lg leading-none") { plain("⠿") }
      end

      td(class: "px-4 py-3") do
        div(id: "view-#{item.id}", class: "flex items-center gap-3") do
          div(class: "stock-logo-wrap flex-shrink-0 w-8 h-8 relative") do
            img(
              src:              "https://assets.parqet.com/logos/symbol/#{item.symbol}?format=jpg",
              alt:              item.symbol,
              class:            "stock-logo w-8 h-8 rounded-full object-contain border border-gray-100 bg-white",
              data_fallback:    "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/#{item.symbol}.png",
              data_initials:    item.symbol.first(2)
            )
            span(
              class: "stock-logo-fallback w-8 h-8 rounded-full bg-gray-800 text-white text-xs font-bold items-center justify-center",
              style: "display:none"
            ) { plain(item.symbol.first(2)) }
          end
          button(
            type:  "button",
            data:  { fetch_news: item.symbol },
            title: "查看 #{item.symbol} 相關新聞",
            class: "font-mono font-bold text-gray-900 hover:text-blue-600 transition-colors cursor-pointer"
          ) { plain(item.symbol) }
          button(
            type:  "button",
            data:  { start_analysis: item.symbol },
            title: "歐歐AI分析 #{item.symbol}",
            class: "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium " \
                   "bg-indigo-50 text-indigo-600 rounded-full border border-indigo-200 " \
                   "hover:bg-indigo-100 hover:border-indigo-400 transition-colors cursor-pointer"
          ) { plain("🐱 分析") }
        end
        form(
          id:     "edit-form-#{item.id}",
          action: "/momentum/watchlist/#{item.id}",
          method: "post",
          class:  "hidden flex gap-1 items-center"
        ) do
          input(type: "hidden", name: "_method",             value: "patch")
          input(type: "hidden", name: "authenticity_token",  value: helpers.form_authenticity_token)
          input(
            type:      "text",
            name:      "symbol",
            value:     item.symbol,
            maxlength: 10,
            class:     "w-24 px-2 py-1 text-xs border border-blue-300 rounded font-mono " \
                       "uppercase focus:outline-none focus:ring-1 focus:ring-blue-400"
          )
          button(type: "submit",
                 class: "text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700") do
            plain("儲存")
          end
          button(type: "button",
                 data: { cancel_edit: item.id },
                 class: "text-xs px-2 py-1 text-gray-500 hover:text-gray-700") do
            plain("取消")
          end
        end
      end

      td(class: "px-4 py-3 text-right") do
        span(class: "font-semibold text-gray-900") { plain(stock ? fmt_currency(stock[:price]) : "—") }
      end

      td(class: "px-4 py-3 text-right") { render_change(stock) }

      td(class: "px-4 py-3 text-right text-gray-500 hidden md:table-cell") do
        plain(stock&.dig(:volume) ? fmt_large(stock[:volume].to_f) : "—")
      end

      td(class: "px-4 py-3 text-sm text-gray-500 hidden md:table-cell") do
        render_range(stock)
      end

      td(class: "px-2 py-3") do
        div(class: "flex items-center justify-end gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity") do
          button(
            type:  "button",
            data:  { start_edit: item.id },
            class: "p-1.5 text-gray-400 hover:text-blue-600 rounded transition-colors",
            title: "編輯"
          ) { plain("✏️") }

          form(action: "/momentum/watchlist/#{item.id}", method: "post", class: "inline") do
            input(type: "hidden", name: "_method",            value: "delete")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            button(
              type:  "submit",
              data:  { confirm: "確定刪除 #{item.symbol}？" },
              class: "p-1.5 text-gray-400 hover:text-red-600 rounded transition-colors",
              title: "刪除"
            ) { plain("🗑️") }
          end
        end
      end
    end
  end

  def render_range(stock)
    has_day = stock && stock[:day_high] && stock[:day_low] && stock[:day_high] > stock[:day_low]
    has_52w = stock && stock[:high_52w] && stock[:low_52w]

    return plain("—") unless has_day || has_52w

    price = stock[:price]
    div(class: "min-w-44 text-xs text-gray-500 space-y-2") do
      if has_day
        render_range_bar("當日價格範圍", stock[:day_low], stock[:day_high], price,
                         "bg-red-400", "text-red-500")
      end
      if has_52w
        render_range_bar("52週範圍", stock[:low_52w], stock[:high_52w], price,
                         "bg-gray-400", "text-gray-500")
      end
    end
  end

  def render_range_bar(label, low, high, price, fill_class, marker_class)
    range = high - low
    pct   = range > 0 && price ? ((price - low) / range * 100).clamp(0, 100).round(1) : nil

    div do
      div(class: "text-center text-gray-400 mb-0.5") { plain(label) }
      div(class: "flex items-center gap-1.5") do
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(low)) }
        div(class: "relative flex-1 pb-2.5") do
          div(class: "h-1 bg-gray-200 rounded-full") do
            div(class: "h-full #{fill_class} rounded-full", style: "width:#{pct || 0}%")
          end
          if pct
            div(
              class: "absolute top-1.5 #{marker_class} leading-none",
              style: "left:calc(#{pct}% - 4px); font-size:8px"
            ) { plain("▲") }
          end
        end
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(high)) }
      end
    end
  end

  def render_change(stock)
    return span(class: "text-gray-400") { plain("—") } unless stock&.dig(:change_pct)

    pct   = stock[:change_pct]
    sign  = pct >= 0 ? "+" : ""
    color = change_color(pct)
    div do
      div(class: "font-medium #{color}") { plain("#{sign}#{sprintf('%.2f', pct * 100)}%") }
      if stock[:change]
        csign = stock[:change] >= 0 ? "+" : ""
        div(class: "text-xs #{color} opacity-75") { plain("#{csign}#{fmt_currency(stock[:change])}") }
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
