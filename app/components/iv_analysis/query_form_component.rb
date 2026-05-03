# frozen_string_literal: true

class IvAnalysis::QueryFormComponent < ApplicationComponent
  def view_template
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6 mb-6") do
      h2(class: "text-base font-semibold text-gray-800 mb-4") { plain "IV 查詢" }
      form(id: "iv-analysis-form", class: "grid grid-cols-2 gap-4 sm:grid-cols-4") do
        div do
          label(for: "iv-ticker", class: "block text-xs font-medium text-gray-600 mb-1") { plain "Ticker" }
          input(
            id:          "iv-ticker",
            name:        "ticker",
            type:        "text",
            placeholder: "AAPL",
            maxlength:   "10",
            class:       "w-full px-3 py-2 rounded-lg border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400 uppercase"
          )
        end
        div do
          label(for: "iv-strike", class: "block text-xs font-medium text-gray-600 mb-1") { plain "Strike" }
          input(
            id:          "iv-strike",
            name:        "strike",
            type:        "number",
            placeholder: "200",
            step:        "0.5",
            min:         "0",
            class:       "w-full px-3 py-2 rounded-lg border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
          )
        end
        div do
          label(for: "iv-expiry", class: "block text-xs font-medium text-gray-600 mb-1") { plain "到期日" }
          select(
            id:    "iv-expiry",
            name:  "expiry_date",
            class: "w-full px-3 py-2 rounded-lg border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400 bg-white"
          ) do
            groups     = expiry_groups
            first_date = groups.values.first&.first
            groups.each do |group_label, dates|
              optgroup(label: group_label) do
                dates.each do |d|
                  val  = d.strftime("%Y-%m-%d")
                  lbl  = d.strftime("%Y/%m/%d")
                  if d == first_date
                    option(value: val, selected: true) { plain lbl }
                  else
                    option(value: val) { plain lbl }
                  end
                end
              end
            end
          end
        end
        div do
          label(class: "block text-xs font-medium text-gray-600 mb-1") { plain "類型" }
          div(class: "flex rounded-lg border border-gray-300 overflow-hidden text-sm") do
            button(
              type:    "button",
              id:      "iv-type-call",
              class:   "flex-1 py-2 bg-blue-600 text-white font-medium transition-colors",
              data:    { type: "call" }
            ) { plain "Call" }
            button(
              type:    "button",
              id:      "iv-type-put",
              class:   "flex-1 py-2 bg-white text-gray-600 hover:bg-gray-50 font-medium transition-colors",
              data:    { type: "put" }
            ) { plain "Put" }
          end
          input(id: "iv-option-type", name: "option_type", type: "hidden", value: "call")
        end
        div(class: "col-span-2 sm:col-span-4 flex items-center gap-3") do
          button(
            id:    "iv-submit-btn",
            type:  "submit",
            class: "px-5 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
          ) { plain "查詢 IV" }
          div(id: "iv-error-msg", class: "hidden text-sm text-red-600 flex-1")
        end
      end
    end
  end

  private

  def expiry_groups
    today    = Date.today
    next_fri = today + 1
    next_fri += 1 until next_fri.friday?
    all_fridays = (0..51).map { |i| next_fri + (i * 7) }

    weekly  = all_fridays.first(6)
    monthly = all_fridays.drop(6).select { |d| d.day.between?(15, 21) }

    { "近期（週選）" => weekly, "月選 / LEAPS" => monthly }
  end
end
