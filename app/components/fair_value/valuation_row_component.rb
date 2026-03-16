# frozen_string_literal: true

class FairValue::ValuationRowComponent < ApplicationComponent
  # @param method_name [String] Valuation method label (e.g. "DCF", "P/E")
  # @param fair_value [Float, nil] Calculated fair value
  # @param current_price [Float, nil] Current market price
  # @param note [String, nil] Short note about inputs used
  # @param formula [String, nil] Detailed formula explanation
  # @param currency [String] Currency code
  # @param show_formula [Boolean] Render the formula row below the main row
  # @param stripe [Boolean] Use striped row background
  # @param highlight [Boolean] Highlight this row (primary method)
  def initialize(
    method_name:,
    fair_value:,
    current_price: nil,
    note: nil,
    formula: nil,
    currency: "USD",
    show_formula: false,
    stripe: false,
    highlight: false
  )
    @method_name   = method_name
    @fair_value    = fair_value
    @current_price = current_price
    @note          = note
    @formula       = formula
    @currency      = currency
    @show_formula  = show_formula
    @stripe        = stripe
    @highlight     = highlight
  end

  def view_template
    row_class = if @highlight
      "bg-blue-50 border-l-4 border-blue-400"
    elsif @stripe
      "bg-gray-50"
    else
      "bg-white"
    end

    tr(class: "#{row_class} border-b border-gray-100 hover:bg-gray-50 transition-colors") do
      td(class: "px-4 py-3 font-mono text-sm font-semibold text-blue-700 w-24") { plain(@method_name) }
      td(class: "px-4 py-3 text-sm font-medium text-gray-700") do
        plain(@fair_value ? fmt_currency(@fair_value, currency: @currency) : "—")
      end
      td(class: "px-4 py-3 text-sm #{upside_class} text-right tabular-nums") { plain(upside_text) }
      td(class: "px-4 py-3 text-xs text-gray-500 hidden sm:table-cell") { plain(@note || "") }
    end
    if @show_formula && @formula
      tr(class: "border-b border-gray-100 bg-blue-50/40") do
        td(colspan: "4", class: "px-4 pb-2 pt-0") do
          p(class: "text-xs text-blue-700 bg-blue-50 rounded px-3 py-1.5 font-mono") { plain(@formula) }
        end
      end
    end
  end

  private

  def upside
    return nil unless @fair_value && @current_price&.positive?

    ((@fair_value - @current_price) / @current_price * 100).round(1)
  end

  def upside_text
    u = upside
    return "—" if u.nil?

    "#{u >= 0 ? '+' : ''}#{u}%"
  end

  def upside_class
    u = upside
    return "text-gray-400" if u.nil?

    if    u >= 20  then "text-green-600 font-semibold"
    elsif u >= 0   then "text-green-500"
    elsif u >= -10 then "text-yellow-600"
    else                "text-red-600"
    end
  end
end
