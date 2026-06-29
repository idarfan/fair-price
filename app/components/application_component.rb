# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Rails.application.routes.url_helpers
  include ActionView::Helpers::NumberHelper

  # Shared semantic color palette.  Subcomponents reference these constants
  # and add their own keys (icon:, label:) via .merge — no copy-pasting.
  SIGNAL_COLORS = {
    confirm_bull: { bg: "bg-green-50",  border: "border-green-300", text: "text-green-800", dot: "bg-green-400" }.freeze,
    caution:      { bg: "bg-yellow-50", border: "border-yellow-300", text: "text-yellow-800", dot: "bg-yellow-400" }.freeze,
    warning:      { bg: "bg-orange-50", border: "border-orange-300", text: "text-orange-800", dot: "bg-orange-400" }.freeze,
    confirm_bear: { bg: "bg-red-50",    border: "border-red-300",    text: "text-red-800",   dot: "bg-red-400"   }.freeze,
    neutral:      { bg: "bg-gray-50",   border: "border-gray-300",   text: "text-gray-600",  dot: "bg-gray-400"  }.freeze
  }.freeze

  private

  def fmt_currency(value, currency: "USD", decimals: 2)
    return "—" if value.nil?

    symbol = currency == "TWD" ? "NT$" : "$"
    "#{symbol}#{number_with_precision(value, precision: decimals, delimiter: ',')}"
  end

  def fmt_percent(value, decimals: 1)
    return "—" if value.nil?

    "#{number_with_precision(value * 100, precision: decimals)}%"
  end

  def fmt_large(value, currency: "USD")
    return "—" if value.nil?

    symbol = currency == "TWD" ? "NT$" : "$"
    abs = value.abs
    if    abs >= 1_000_000_000_000 then "#{symbol}#{number_with_precision(value / 1_000_000_000_000.0, precision: 2)}T"
    elsif abs >= 1_000_000_000     then "#{symbol}#{number_with_precision(value / 1_000_000_000.0, precision: 2)}B"
    elsif abs >= 1_000_000         then "#{symbol}#{number_with_precision(value / 1_000_000.0, precision: 2)}M"
    else                                fmt_currency(value, currency: currency)
    end
  end

  def upside_color(upside_pct)
    if    upside_pct >= 20  then "text-green-600 font-semibold"
    elsif upside_pct >= 0   then "text-green-500"
    elsif upside_pct >= -10 then "text-yellow-600"
    else                         "text-red-600"
    end
  end

  def change_color(value)
    return "text-gray-400" if value.nil?

    value >= 0 ? "text-green-600" : "text-red-600"
  end
end
