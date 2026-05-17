# frozen_string_literal: true

class IvWatchlists::IndexView::AddSymbolForm < ApplicationComponent
  QUICK_SYMBOLS = %w[AAPL NVDA TSLA MSFT AMZN META GOOGL AMD].freeze

  def view_template
    div(class: "bg-gray-900 border border-gray-700 rounded-xl p-6") do
      h2(class: "text-sm font-medium text-gray-300 mb-4") { "新增標的" }
      form(action: "/iv_watchlists", method: "post", class: "flex flex-col sm:flex-row gap-3") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        input(
          type: "text", name: "iv_watchlist[symbol]",
          placeholder: "美股代號，例如 NVDA", maxlength: "10", autocomplete: "off",
          class: "flex-1 bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-500 uppercase focus:outline-none focus:border-blue-500 transition-colors",
          data: { watchlist_form_target: "input" }
        )
        select(
          name: "iv_watchlist[group_tag]",
          class: "bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-gray-300 focus:outline-none focus:border-blue-500 transition-colors"
        ) do
          IvWatchlist::GROUP_TAGS.each { |tag| option(value: tag) { tag.capitalize } }
        end
        button(
          type: "submit",
          class: "bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2 transition-colors whitespace-nowrap"
        ) { "+ 加入" }
      end
      div(class: "mt-4") do
        p(class: "text-xs text-gray-500 mb-2") { "快速加入：" }
        div(class: "flex flex-wrap gap-2") do
          QUICK_SYMBOLS.each do |sym|
            button(
              type: "button",
              class: "px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 border border-gray-600 rounded-full transition-colors cursor-pointer",
              data: { symbol: sym, action: "click->watchlist-form#quickAdd" }
            ) { sym }
          end
        end
      end
    end
  end
end

