# frozen_string_literal: true

class FairValue::ValuationTableComponent < ApplicationComponent
  # @param valuations [Array<Hash>] Array with :method, :value, :note, :formula keys
  # @param current_price [Float, nil] Market price for upside calculation
  # @param currency [String] Currency code
  # @param show_formulas [Boolean] Show detailed formula rows
  # @param caption [String, nil] Table caption (title above table)
  # @param highlight_first [Boolean] Highlight the first (primary) method row
  def initialize(
    valuations:,
    current_price: nil,
    currency: "USD",
    show_formulas: false,
    caption: nil,
    highlight_first: true
  )
    @valuations      = valuations
    @current_price   = current_price
    @currency        = currency
    @show_formulas   = show_formulas
    @caption         = caption
    @highlight_first = highlight_first
  end

  def view_template
    return if @valuations.empty?

    div(class: "space-y-2") do
      if @caption
        h3(class: "text-base font-semibold text-gray-700") { plain(@caption) }
      end
      div(class: "overflow-x-auto rounded-xl border border-gray-200 shadow-sm") do
        table(class: "w-full text-left border-collapse") do
          thead do
            tr(class: "bg-gray-100 border-b-2 border-gray-200") do
              th(class: "px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide w-24") { plain("方法") }
              th(class: "px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide") { plain("公允價值") }
              th(class: "px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide text-right") { plain("漲跌空間") }
              th(class: "px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide hidden sm:table-cell") { plain("說明") }
            end
          end
          tbody do
            @valuations.each_with_index do |v, i|
              render FairValue::ValuationRowComponent.new(
                method_name:   v[:method],
                fair_value:    v[:value],
                current_price: @current_price,
                note:          v[:note],
                formula:       v[:formula],
                currency:      @currency,
                show_formula:  @show_formulas,
                stripe:        i.odd?,
                highlight:     @highlight_first && i.zero?
              )
            end
          end
        end
      end
      if @show_formulas
        label(class: "flex items-center gap-2 text-xs text-gray-500 cursor-pointer mt-1") do
          plain("公式展開顯示中")
        end
      end
    end
  end
end
