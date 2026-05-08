# frozen_string_literal: true

class IvAnalysis::DashboardComponent < ApplicationComponent
  def view_template
    div(class: "mb-6") do
      div(class: "flex items-center justify-between mb-3") do
        h2(class: "text-base font-semibold text-gray-800") { plain "IV Rank 儀表板" }
        span(class: "text-xs text-gray-400") { plain "點擊卡片快速填入 Ticker" }
      end

      # Summary bar — shown after JS loads data
      div(id: "iv-dashboard-summary", class: "hidden grid grid-cols-3 gap-3 mb-4") do
        div(class: "rounded-lg p-3 text-center bg-red-50") do
          div(class: "text-xs font-medium text-red-700") { plain "High IV · IVR ≥ 60" }
          div(id: "iv-summary-high-count", class: "text-2xl font-bold text-red-600 mt-1") { plain "—" }
        end
        div(class: "rounded-lg p-3 text-center bg-orange-50") do
          div(class: "text-xs font-medium text-orange-700") { plain "Neutral · 30–60" }
          div(id: "iv-summary-mid-count", class: "text-2xl font-bold text-orange-500 mt-1") { plain "—" }
        end
        div(class: "rounded-lg p-3 text-center bg-green-50") do
          div(class: "text-xs font-medium text-green-700") { plain "Low IV · IVR < 30" }
          div(id: "iv-summary-low-count", class: "text-2xl font-bold text-green-600 mt-1") { plain "—" }
        end
      end

      # Gauge cards — populated by JS
      div(
        id:    "iv-dashboard-cards",
        class: "flex flex-wrap gap-3 min-h-16"
      ) do
        span(class: "text-sm text-gray-400 self-center") { plain "載入中…" }
      end
    end
  end
end
