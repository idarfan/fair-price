# frozen_string_literal: true

class IvAnalysis::WatchlistComponent < ApplicationComponent
  def view_template
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm") do
      div(class: "px-6 py-4 border-b border-gray-100 flex items-center justify-between") do
        h2(class: "text-base font-semibold text-gray-800") { plain "IV Watchlist" }
        button(
          id:    "iv-watchlist-refresh",
          type:  "button",
          class: "text-xs text-blue-500 hover:text-blue-700 transition-colors"
        ) { plain "重新整理" }
      end
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          thead do
            tr(class: "bg-gray-50 border-b border-gray-100") do
              th(class: "text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "Ticker" }
              th(class: "text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "ATM IV" }
              th(class: "text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "內涵價值" }
              th(class: "text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "時間價值" }
              th(class: "text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "累積天數" }
              th(class: "text-center px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "資料品質" }
              th(class: "text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain "最後更新" }
              th(class: "px-4 py-2.5") {}
            end
          end
          tbody(id: "iv-watchlist-body") do
            tr do
              td(colspan: "8", class: "px-4 py-8 text-center text-sm text-gray-400") { plain "載入中…" }
            end
          end
        end
      end
    end
  end
end
