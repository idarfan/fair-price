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
    render Shared::OwnershipPanelComponent.new
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

  def render_script
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
        })();
      JS
    end
  end
end
