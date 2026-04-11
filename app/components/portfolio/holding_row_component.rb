# frozen_string_literal: true

class Portfolio::HoldingRowComponent < ApplicationComponent
  # @param holding [Portfolio]
  # @param quote   [Hash, nil]  Finnhub quote { "c", "d", "dp", ... }
  def initialize(holding:, quote: nil)
    @holding   = holding
    @presenter = Portfolio::HoldingPresenter.new(holding: holding, quote: quote)
  end

  def view_template
    tr(
      id:    "holding-#{@holding.id}",
      data:  { id: @holding.id, shares: @holding.shares.to_f, unit_cost: @holding.unit_cost.to_f },
      class: "border-t border-gray-100 hover:bg-gray-50 transition-colors group"
    ) do
      render_drag_handle
      render_symbol
      render_shares
      render_price
      render_change_amount
      render_change_pct
      render_market_value
      render_unit_cost
      render_total_cost
      render_pnl_amount
      render_pnl_pct
      render_sell_price
      render_profit
      render_actions
    end
  end

  private

  def price         = @presenter.price
  def market_value  = @presenter.market_value
  def pnl_amount    = @presenter.pnl_amount
  def pnl_pct       = @presenter.pnl_pct

  TD = "px-2 py-2 text-right"

  def render_drag_handle
    td(class: "px-1 py-2 text-center") do
      span(class: "drag-handle cursor-grab active:cursor-grabbing text-gray-300 " \
                  "hover:text-gray-500 select-none leading-none") { plain("⠿") }
    end
  end

  def render_symbol
    td(class: "px-2 py-2 cursor-pointer select-none",
       data:  { ownership_symbol: @holding.symbol },
       title: "查看 #{@holding.symbol} 持股結構") do
      div(class: "flex items-center gap-1.5") do
        div(class: "flex-shrink-0 w-6 h-6 relative") do
          img(
            src:           "https://assets.parqet.com/logos/symbol/#{@holding.symbol}?format=jpg",
            alt:           @holding.symbol,
            class:         "stock-logo w-6 h-6 rounded-full object-contain border border-gray-100 bg-white",
            data_fallback: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/#{@holding.symbol}.png",
            data_initials: @holding.symbol.first(2)
          )
          span(
            class: "stock-logo-fallback absolute inset-0 rounded-full bg-gray-800 text-white font-bold items-center justify-center",
            style: "display:none; font-size:8px"
          ) { plain(@holding.symbol.first(2)) }
        end
        span(class: "font-mono font-bold text-gray-900 text-xs") { plain(@holding.symbol) }
      end
    end
  end

  def render_shares
    td(class: "#{TD} text-gray-700 text-xs") { plain(fmt_shares) }
  end

  def render_price
    td(class: "#{TD}", id: "cell-price-#{@holding.id}") do
      if price&.positive?
        span(class: "font-semibold text-gray-900 text-xs") { plain(fmt_currency(price)) }
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_change_amount
    td(class: "#{TD}", id: "cell-changed-#{@holding.id}") do
      val = @quote&.dig("d")&.to_f
      if val
        span(class: "text-xs #{change_color(val / price.to_f)}") do
          plain("#{val >= 0 ? '+' : ''}#{fmt_currency(val)}")
        end
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_change_pct
    td(class: "#{TD}", id: "cell-changedp-#{@holding.id}") do
      val = @quote&.dig("dp")&.to_f
      if val
        span(class: "text-xs font-medium #{change_color(val / 100.0)}") do
          plain("#{val >= 0 ? '+' : ''}#{sprintf('%.2f', val)}%")
        end
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_market_value
    td(class: "#{TD} text-gray-700", id: "cell-mktval-#{@holding.id}") do
      market_value ? span(class: "text-xs") { plain(fmt_currency(market_value)) } : span(class: "text-gray-300") { plain("—") }
    end
  end

  def render_unit_cost
    td(class: "#{TD} text-gray-500 text-xs") { plain(fmt_currency(@holding.unit_cost)) }
  end

  def render_total_cost
    td(class: "#{TD} text-gray-500 text-xs") { plain(fmt_currency(@holding.total_cost)) }
  end

  def render_pnl_amount
    td(class: "#{TD} font-semibold", id: "cell-pnl-#{@holding.id}") do
      if pnl_amount
        color = pnl_amount >= 0 ? "text-green-600" : "text-red-500"
        span(class: "text-xs #{color}") { plain("#{pnl_amount >= 0 ? '+' : ''}#{fmt_currency(pnl_amount)}") }
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_pnl_pct
    td(class: "#{TD} font-semibold", id: "cell-pnlpct-#{@holding.id}") do
      if pnl_pct
        color = pnl_pct >= 0 ? "text-green-600" : "text-red-500"
        span(class: "text-xs #{color}") { plain("#{pnl_pct >= 0 ? '+' : ''}#{sprintf('%.2f', pnl_pct)}%") }
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_sell_price
    td(class: "#{TD}") do
      form(action: "/portfolio/#{@holding.id}", method: "post",
           class: "inline-flex items-center gap-1",
           id:    "sell-form-#{@holding.id}") do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        input(type: "hidden", name: "portfolio[symbol]",     value: @holding.symbol)
        input(type: "hidden", name: "portfolio[shares]",     value: @holding.shares.to_f)
        input(type: "hidden", name: "portfolio[unit_cost]",  value: @holding.unit_cost.to_f)
        input(
          type:        "number",
          name:        "portfolio[sell_price]",
          value:       @holding.sell_price&.to_f,
          placeholder: "—",
          step:        "0.01", min: "0",
          id:          "sell-price-#{@holding.id}",
          class:       "w-20 px-1.5 py-0.5 text-xs text-right border border-gray-200 rounded " \
                       "focus:outline-none focus:ring-1 focus:ring-blue-300 font-mono"
        )
        button(type: "submit",
               class: "text-xs text-blue-500 hover:text-blue-700 transition-colors") { plain("✓") }
      end
    end
  end

  def render_profit
    td(class: "#{TD}") do
      initial = @holding.profit_if_sold&.round(2)
      input(
        type:        "number",
        value:       initial,
        placeholder: "—",
        step:        "0.01",
        id:          "profit-input-#{@holding.id}",
        data: {
          holding_id: @holding.id,
          unit_cost:  @holding.unit_cost.to_f,
          shares:     @holding.shares.to_f
        },
        class: "w-24 px-1.5 py-0.5 text-xs text-right border border-gray-200 rounded " \
               "focus:outline-none focus:ring-1 focus:ring-green-300 font-mono " \
               "#{initial && initial >= 0 ? 'text-green-600' : (initial ? 'text-red-500' : '')}"
      )
    end
  end

  def render_actions
    td(class: "px-2 py-2 text-right") do
      form(action: "/portfolio/#{@holding.id}", method: "post",
           class: "inline",
           data:  { confirm_delete: "確定刪除 #{@holding.symbol}？" }) do
        input(type: "hidden", name: "_method",            value: "delete")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(type: "submit",
               class: "text-xs px-1.5 py-0.5 rounded border border-red-100 text-red-400 " \
                      "opacity-0 group-hover:opacity-100 hover:bg-red-50 transition-all") { plain("刪除") }
      end
    end
  end

  def fmt_shares
    @presenter.fmt_shares
  end
end
