# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Rails.application.routes.url_helpers
  include ActionView::Helpers::NumberHelper

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
