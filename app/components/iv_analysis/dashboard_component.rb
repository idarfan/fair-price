# frozen_string_literal: true

class IvAnalysis::DashboardComponent < ApplicationComponent
  def view_template
    div(class: "mb-6") do
      div(class: "flex items-center justify-between mb-3") do
        div(class: "flex items-center gap-3") do
          h2(class: "text-base font-semibold text-gray-800") { plain "儀表板" }
          div(class: "flex rounded-lg overflow-hidden border border-gray-200 text-xs font-medium") do
            button(
              id: "dash-mode-ivr",
              data: { mode: "ivr" },
              class: "px-3 py-1.5 bg-orange-500 text-white transition-colors"
            ) { plain "IV Rank" }
            button(
              id: "dash-mode-skew",
              data: { mode: "skew" },
              class: "px-3 py-1.5 bg-white text-gray-600 hover:bg-gray-50 transition-colors"
            ) { plain "Skew Rank" }
          end
        end
        span(class: "text-xs text-gray-400") { plain "點擊卡片快速填入 Ticker" }
      end

      div(id: "iv-dashboard-summary", class: "hidden grid grid-cols-3 gap-3 mb-4") do
        div(id: "dash-sum-high-box", class: "rounded-lg p-3 text-center bg-red-50") do
          div(id: "dash-sum-high-label", class: "text-xs font-medium text-red-700") { plain "High Vol · IVR ≥ 60" }
          div(id: "iv-summary-high-count", class: "text-2xl font-bold text-red-600 mt-1") { plain "—" }
        end
        div(id: "dash-sum-mid-box", class: "rounded-lg p-3 text-center bg-gray-50") do
          div(id: "dash-sum-mid-label", class: "text-xs font-medium text-gray-600") { plain "Neutral · 30–60" }
          div(id: "iv-summary-mid-count", class: "text-2xl font-bold text-gray-500 mt-1") { plain "—" }
        end
        div(id: "dash-sum-low-box", class: "rounded-lg p-3 text-center bg-green-50") do
          div(id: "dash-sum-low-label", class: "text-xs font-medium text-green-700") { plain "Low Vol · IVR < 30" }
          div(id: "iv-summary-low-count", class: "text-2xl font-bold text-green-600 mt-1") { plain "—" }
        end
      end

      div(id: "iv-dashboard-cards", class: "flex flex-wrap gap-3 min-h-16") do
        span(class: "text-sm text-gray-400 self-center") { plain "載入中…" }
      end
    end
  end
end
