# frozen_string_literal: true

class IvAnalysis::ResultComponent < ApplicationComponent
  def view_template
    div(id: "iv-result-section", class: "hidden mb-6") do
      div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
        div(class: "flex items-center justify-between mb-4") do
          h2(class: "text-base font-semibold text-gray-800") do
            plain "查詢結果："
            span(id: "iv-result-ticker", class: "text-blue-600 ml-1")
          end
          span(id: "iv-result-time", class: "text-xs text-gray-400")
        end

        # strike snap warning
        div(id: "iv-snap-warning", class: "hidden mb-3 px-4 py-2.5 rounded-lg text-sm bg-amber-50 border border-amber-200 text-amber-800")

        # data quality banner
        div(id: "iv-quality-banner", class: "hidden mb-4 px-4 py-2.5 rounded-lg text-sm")

        # metric cards — row 1: price / delta / strike IV
        div(class: "grid grid-cols-3 gap-4 mb-3") do
          metric_card("iv-card-price",  "當前股價",   "$—")
          metric_card("iv-card-delta",  "Delta",      "—")
          metric_card("iv-card-iv",     "Strike IV",  "—%")
        end

        # metric cards — row 2: DTE / ATM IV / HV (21d)
        div(class: "grid grid-cols-3 gap-4 mb-5") do
          metric_card("iv-card-dte",    "DTE",        "— 天")
          metric_card("iv-card-atm",    "ATM IV",     "—%")
          metric_card("iv-card-hv21",   "HV (21d)",   "—%")
        end

        # IVR/IVP table
        div(class: "overflow-x-auto") do
          table(class: "w-full text-sm") do
            thead do
              tr(class: "border-b border-gray-100") do
                th(class: "text-left pb-2 text-xs text-gray-500 font-medium") { plain "指標" }
                th(class: "text-center pb-2 text-xs text-gray-500 font-medium") { plain "1 年" }
                th(class: "text-center pb-2 text-xs text-gray-500 font-medium") { plain "2 年" }
              end
            end
            tbody do
              ivr_row("IV Rank (IVR)", "iv-ivr-1y", "iv-ivr-2y")
              ivr_row("IV Percentile (IVP)", "iv-ivp-1y", "iv-ivp-2y")
            end
          end
        end

        # conclusion card
        div(id: "iv-conclusion", class: "hidden mt-4 px-4 py-3 rounded-lg text-sm")
      end
    end
  end

  private

  def metric_card(id, label, default)
    div(class: "bg-gray-50 rounded-lg p-3 text-center") do
      p(class: "text-xs text-gray-500 mb-1") { plain label }
      p(id: id, class: "text-lg font-bold text-gray-800") { plain default }
    end
  end

  def ivr_row(label, id_1y, id_2y)
    tr(class: "border-b border-gray-50") do
      td(class: "py-2 text-gray-600") { plain label }
      td(id: id_1y, class: "py-2 text-center font-medium") { plain "—" }
      td(id: id_2y, class: "py-2 text-center font-medium") { plain "—" }
    end
  end
end
