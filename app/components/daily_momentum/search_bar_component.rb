# frozen_string_literal: true

class DailyMomentum::SearchBarComponent < ApplicationComponent
  def view_template
    div(class: "flex gap-2 items-center") do
      form(action: "/momentum/watchlist", method: "post", class: "flex gap-2 flex-1") do
        input(type: "hidden", name: "authenticity_token",
              value: helpers.form_authenticity_token)
        input(
          type: "text",
          name: "symbol",
          placeholder: "輸入美股代號（如 AAPL、NVDA）",
          maxlength: 10,
          autocomplete: "off",
          autocapitalize: "characters",
          class: "flex-1 px-3 py-2 text-sm border border-gray-300 rounded-lg " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-300 focus:border-blue-400 " \
                 "font-mono uppercase placeholder:normal-case placeholder:font-sans"
        )
        button(
          type: "submit",
          class: "px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm " \
                 "font-medium rounded-lg transition-colors flex items-center gap-1.5"
        ) do
          span { plain("＋") }
          span { plain("加入觀察名單") }
        end
      end
    end
  end
end
