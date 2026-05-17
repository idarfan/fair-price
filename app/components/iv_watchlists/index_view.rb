# frozen_string_literal: true

class IvWatchlists::IndexView < ApplicationComponent
  GROUP_COLORS = {
    "index"     => "bg-blue-500/10 text-blue-300 border-blue-500/30",
    "leveraged" => "bg-orange-500/10 text-orange-300 border-orange-500/30",
    "macro"     => "bg-purple-500/10 text-purple-300 border-purple-500/30",
    "general"   => "bg-gray-500/10 text-gray-300 border-gray-500/30"
  }.freeze

  def initialize(grouped:, new_item:)
    @grouped  = grouped
    @new_item = new_item
  end

  def view_template
    div(class: "max-w-3xl mx-auto px-4 py-8") do
      div(class: "mb-8") do
        h1(class: "text-2xl font-semibold text-gray-900") { "IV Skew 追蹤清單" }
        p(class: "text-gray-600 text-sm mt-1") { "管理每日自動抓取 IV Skew 的美股標的" }
      end

      render AddSymbolForm.new

      if @grouped.empty?
        div(class: "text-center text-gray-500 py-12") { "清單為空，請先加入標的" }
      else
        div(class: "space-y-6 mt-8") do
          @grouped.each { |group_tag, items| render GroupSection.new(group_tag:, items:) }
        end
      end
    end
    render_scripts
  end

  private

  def render_scripts
    script do
      raw <<~JS.html_safe
        (function() {
          var csrf = function() {
            var m = document.querySelector('meta[name="csrf-token"]');
            return m ? m.content : '';
          };

          document.addEventListener('click', async function(e) {
            // Toggle active
            var toggleBtn = e.target.closest('[data-action="click->watchlist#toggle"]');
            if (toggleBtn) {
              var res = await fetch(toggleBtn.dataset.url, {
                method: 'PATCH',
                headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
              });
              var data = await res.json();
              if (!data.success) return;
              toggleBtn.classList.toggle('bg-green-600', data.active);
              toggleBtn.classList.toggle('bg-gray-600', !data.active);
              var dot = toggleBtn.querySelector('span');
              dot.classList.toggle('left-5', data.active);
              dot.classList.toggle('left-1', !data.active);
              return;
            }

            // Remove
            var removeBtn = e.target.closest('[data-action="click->watchlist#remove"]');
            if (removeBtn) {
              if (!confirm('確定移除 ' + removeBtn.dataset.symbol + '？')) return;
              var res = await fetch(removeBtn.dataset.url, {
                method: 'DELETE',
                headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
              });
              var data = await res.json();
              if (data.success) {
                var row = document.getElementById('watchlist-row-' + removeBtn.dataset.id);
                if (row) row.remove();
              }
              return;
            }

            // Quick add chip
            var chip = e.target.closest('[data-action="click->watchlist-form#quickAdd"]');
            if (chip) {
              var input = document.querySelector('[data-watchlist-form-target="input"]');
              if (input) { input.value = chip.dataset.symbol; input.focus(); }
            }
          });
        })();
      JS
    end
  end

  # ── 新增表單 ────────────────────────────────────────────
  class AddSymbolForm < ApplicationComponent
    QUICK_SYMBOLS = %w[AAPL NVDA TSLA MSFT AMZN META GOOGL AMD].freeze

    def view_template
      div(class: "bg-gray-900 border border-gray-700 rounded-xl p-6") do
        h2(class: "text-sm font-medium text-gray-300 mb-4") { "新增標的" }

        form(
          action: "/iv_watchlists",
          method: "post",
          class: "flex flex-col sm:flex-row gap-3"
        ) do
          input(type: "hidden", name: "authenticity_token",
                value: helpers.form_authenticity_token)

          input(
            type: "text",
            name: "iv_watchlist[symbol]",
            placeholder: "美股代號，例如 NVDA",
            maxlength: "10",
            autocomplete: "off",
            class: "flex-1 bg-gray-800 border border-gray-600 rounded-lg px-4 py-2
                    text-white placeholder-gray-500 uppercase
                    focus:outline-none focus:border-blue-500 transition-colors",
            data: { watchlist_form_target: "input" }
          )

          select(
            name: "iv_watchlist[group_tag]",
            class: "bg-gray-800 border border-gray-600 rounded-lg px-3 py-2
                    text-gray-300 focus:outline-none focus:border-blue-500 transition-colors"
          ) do
            IvWatchlist::GROUP_TAGS.each { |tag| option(value: tag) { tag.capitalize } }
          end

          button(
            type: "submit",
            class: "bg-blue-600 hover:bg-blue-500 text-white font-medium
                    rounded-lg px-5 py-2 transition-colors whitespace-nowrap"
          ) { "+ 加入" }
        end

        div(class: "mt-4") do
          p(class: "text-xs text-gray-500 mb-2") { "快速加入：" }
          div(class: "flex flex-wrap gap-2") do
            QUICK_SYMBOLS.each do |sym|
              button(
                type: "button",
                class: "px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700
                        text-gray-300 border border-gray-600 rounded-full
                        transition-colors cursor-pointer",
                data: { symbol: sym, action: "click->watchlist-form#quickAdd" }
              ) { sym }
            end
          end
        end
      end
    end
  end

  # ── 群組區塊 ────────────────────────────────────────────
  class GroupSection < ApplicationComponent
    def initialize(group_tag:, items:)
      @group_tag = group_tag
      @items     = items
    end

    def view_template
      div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
        div(class: "flex items-center gap-3 px-5 py-3 border-b border-gray-700") do
          span(
            class: "text-xs font-medium px-2 py-0.5 rounded border
                    #{IvWatchlists::IndexView::GROUP_COLORS.fetch(@group_tag,
                        IvWatchlists::IndexView::GROUP_COLORS['general'])}"
          ) { @group_tag.upcase }
          span(class: "text-gray-400 text-sm") { "#{@items.size} 個標的" }
        end

        div(class: "divide-y divide-gray-800") do
          @items.each { |item| render SymbolRow.new(item:) }
        end
      end
    end
  end

  # ── 單行標的 ────────────────────────────────────────────
  class SymbolRow < ApplicationComponent
    def initialize(item:)
      @item = item
    end

    def view_template
      div(
        class: "flex items-center justify-between px-5 py-3
                hover:bg-gray-800/50 transition-colors",
        id: "watchlist-row-#{@item.id}"
      ) do
        div(class: "flex items-center gap-3") do
          span(class: "text-white font-mono font-medium text-sm") { @item.symbol }
          span(class: "text-gray-500 text-xs") {
            "加入於 #{@item.created_at.strftime('%Y/%m/%d')}"
          }
        end

        div(class: "flex items-center gap-3") do
          button(
            type: "button",
            class: "relative w-9 h-5 rounded-full transition-colors
                    #{@item.active? ? 'bg-green-600' : 'bg-gray-600'}",
            data: {
              action: "click->watchlist#toggle",
              url:    "/iv_watchlists/#{@item.id}/toggle",
              id:     @item.id
            },
            title: @item.active? ? "點擊停用" : "點擊啟用"
          ) do
            span(
              class: "absolute top-1 w-3 h-3 bg-white rounded-full transition-all
                      #{@item.active? ? 'left-5' : 'left-1'}"
            )
          end

          button(
            type: "button",
            class: "text-gray-600 hover:text-red-400 transition-colors px-1",
            data: {
              action:  "click->watchlist#remove",
              url:     "/iv_watchlists/#{@item.id}",
              symbol:  @item.symbol,
              id:      @item.id
            },
            title: "移除 #{@item.symbol}"
          ) { "✕" }
        end
      end
    end
  end
end
