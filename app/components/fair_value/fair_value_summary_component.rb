# frozen_string_literal: true

class FairValue::FairValueSummaryComponent < ApplicationComponent
  JUDGMENT_STYLES = {
    "🔴 明顯高估"        => { bg: "bg-red-50",    border: "border-red-300",    text: "text-red-800",    badge: "bg-red-100 text-red-800" },
    "🟡 略微高估"        => { bg: "bg-yellow-50", border: "border-yellow-300", text: "text-yellow-800", badge: "bg-yellow-100 text-yellow-800" },
    "🟢 合理"            => { bg: "bg-green-50",  border: "border-green-300",  text: "text-green-800",  badge: "bg-green-100 text-green-800" },
    "🟡 略微低估"        => { bg: "bg-yellow-50", border: "border-yellow-300", text: "text-yellow-800", badge: "bg-yellow-100 text-yellow-800" },
    "🟢 明顯低估（潛在買點）" => { bg: "bg-green-50",  border: "border-green-300",  text: "text-green-800",  badge: "bg-green-100 text-green-800" },
  }.freeze

  DEFAULT_STYLE = { bg: "bg-gray-50", border: "border-gray-300", text: "text-gray-700", badge: "bg-gray-100 text-gray-700" }.freeze

  # @param fair_value_low [Float, nil] Lowest fair value estimate
  # @param fair_value_high [Float, nil] Highest fair value estimate
  # @param current_price [Float, nil] Current market price
  # @param currency [String] Currency code
  # @param stock_type [String] Stock classification (e.g. "一般股", "金融股")
  # @param growth_rate [Float, nil] Estimated growth rate (as decimal, e.g. 0.12 = 12%)
  # @param growth_rate_note [String, nil] Sources used for growth rate
  # @param judgment [String, nil] Valuation judgment text
  # @param show_details [Boolean] Show growth rate and stock type details
  def initialize(
    fair_value_low:,
    fair_value_high:,
    current_price: nil,
    currency: "USD",
    stock_type: "一般股",
    growth_rate: nil,
    growth_rate_note: nil,
    judgment: nil,
    show_details: true
  )
    @fair_value_low   = fair_value_low
    @fair_value_high  = fair_value_high
    @current_price    = current_price
    @currency         = currency
    @stock_type       = stock_type
    @growth_rate      = growth_rate
    @growth_rate_note = growth_rate_note
    @judgment         = judgment
    @show_details     = show_details
  end

  def view_template
    style = JUDGMENT_STYLES.fetch(@judgment.to_s, DEFAULT_STYLE)

    div(class: "rounded-2xl border-2 #{style[:border]} #{style[:bg]} p-6 space-y-4") do
      # Header row: judgment badge
      div(class: "flex items-start justify-between gap-4") do
        div do
          p(class: "text-xs font-medium text-gray-500 uppercase tracking-wide mb-1") { plain("估值判斷") }
          span(class: "inline-flex items-center text-base font-bold #{style[:text]}") do
            plain(@judgment || "⚪ 資料不足")
          end
        end
        div(class: "text-right") do
          p(class: "text-xs text-gray-500 mb-1") { plain("股票類型") }
          span(class: "inline-block px-2.5 py-0.5 rounded-full text-xs font-semibold #{style[:badge]}") { plain(@stock_type) }
        end
      end

      # Price range
      div(class: "grid grid-cols-3 gap-4 text-center") do
        div do
          p(class: "text-xs text-gray-500") { plain("公允價低估") }
          p(class: "text-lg font-bold text-blue-600") { plain(@fair_value_low ? fmt_currency(@fair_value_low, currency: @currency) : "—") }
        end
        div(class: "flex flex-col items-center") do
          p(class: "text-xs text-gray-500") { plain("目前股價") }
          p(class: "text-lg font-bold #{style[:text]}") { plain(@current_price ? fmt_currency(@current_price, currency: @currency) : "—") }
        end
        div do
          p(class: "text-xs text-gray-500") { plain("公允價高估") }
          p(class: "text-lg font-bold text-blue-600") { plain(@fair_value_high ? fmt_currency(@fair_value_high, currency: @currency) : "—") }
        end
      end

      # Upside/downside bars
      if @fair_value_low && @fair_value_high && @current_price
        div(class: "space-y-1") do
          div(class: "flex justify-between text-xs text-gray-500") do
            span { plain("低估公允價漲跌幅") }
            span { plain("高估公允價漲跌幅") }
          end
          div(class: "flex gap-2") do
            upside_badge(@fair_value_low, "低")
            upside_badge(@fair_value_high, "高")
          end
        end
      end

      # Details section
      if @show_details
        div(class: "border-t border-gray-200 pt-3 grid grid-cols-2 gap-3 text-sm") do
          if @growth_rate
            div do
              p(class: "text-xs text-gray-500") { plain("預估成長率") }
              p(class: "font-semibold text-gray-800") { plain(fmt_percent(@growth_rate)) }
              p(class: "text-xs text-gray-400") { plain(@growth_rate_note) } if @growth_rate_note
            end
          end
          div do
            p(class: "text-xs text-gray-500") { plain("分析方法") }
            p(class: "font-semibold text-gray-800") { plain("#{@stock_type}適用模型") }
          end
        end
      end
    end
  end

  private

  def upside_badge(fair_value, label)
    return unless @current_price&.positive?

    pct = ((fair_value - @current_price) / @current_price * 100).round(1)
    color = pct >= 0 ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"

    div(class: "flex-1 text-center px-3 py-1.5 rounded-lg #{color}") do
      p(class: "text-xs opacity-70") { plain("#{label}估價") }
      p(class: "font-semibold text-sm") { plain("#{pct >= 0 ? '+' : ''}#{pct}%") }
    end
  end
end
