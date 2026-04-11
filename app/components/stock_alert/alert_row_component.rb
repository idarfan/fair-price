# frozen_string_literal: true

class StockAlert::AlertRowComponent < ApplicationComponent
  # @param alert       [PriceAlert]
  # @param market_data [Hash] symbol => Finnhub quote hash
  def initialize(alert:, market_data: {})
    @alert     = alert
    current_price = market_data[alert.symbol]&.dig("c")
    @presenter = PriceAlert::AlertPresenter.new(alert: alert, current_price: current_price)
  end

  def view_template
    tr(
      id: "alert-#{@alert.id}",
      data: { alert_id: @alert.id },
      class: "border-t border-gray-100 hover:bg-gray-50 transition-colors"
    ) do
      render_drag_handle
      render_symbol
      render_current_price
      render_condition
      render_target_price
      render_notes
      render_status
      render_actions
    end
  end

  private

  def render_drag_handle
    td(class: "px-3 py-3") do
      span(class: "drag-handle cursor-grab text-gray-300 hover:text-gray-500 select-none text-base") { plain("⠿") }
    end
  end

  def render_symbol
    td(class: "px-3 py-3 cursor-pointer select-none",
       data:  { ownership_symbol: @alert.symbol },
       title: "查看 #{@alert.symbol} 持股結構") do
      div(class: "flex items-center gap-2") do
        div(class: "flex-shrink-0 w-7 h-7 relative") do
          img(
            src:           "https://assets.parqet.com/logos/symbol/#{@alert.symbol}?format=jpg",
            alt:           @alert.symbol,
            class:         "stock-logo w-7 h-7 rounded-full object-contain border border-gray-100 bg-white",
            data_fallback: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/#{@alert.symbol}.png",
            data_initials: @alert.symbol.first(2)
          )
          span(
            class: "stock-logo-fallback absolute inset-0 rounded-full bg-gray-800 text-white items-center justify-center font-bold",
            style: "display:none; font-size:9px"
          ) { plain(@alert.symbol.first(2)) }
        end
        div do
          span(class: "font-mono font-bold text-gray-900") { plain(@alert.symbol) }
          if @alert.triggered?
            span(class: "ml-1 text-xs text-purple-400") { plain("已觸發") }
          end
        end
      end
    end
  end

  def render_current_price
    td(class: "px-3 py-3 text-right") do
      price = @presenter.current_price_display
      if price
        span(class: "font-semibold #{@presenter.price_color}") { plain("$#{sprintf("%.2f", price)}") }
      else
        span(class: "text-gray-300") { plain("—") }
      end
    end
  end

  def render_condition
    td(class: "px-3 py-3 text-center") do
      form(
        action: "/watchlist/#{@alert.id}/toggle_condition",
        method: "post",
        style: "display:inline"
      ) do
        input(type: "hidden", name: "_method", value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(
          type: "submit",
          title: "點擊切換條件",
          class: condition_button_class
        ) { plain(condition_label) }
      end
    end
  end

  def render_target_price
    td(class: "px-3 py-3 text-right font-mono text-gray-700") do
      plain("$#{sprintf("%.2f", @alert.target_price)}")
    end
  end

  def render_notes
    td(class: "px-3 py-3 text-sm text-gray-400 max-w-32 truncate") do
      plain(@alert.notes.presence || "—")
    end
  end

  def render_status
    td(class: "px-3 py-3 text-center") do
      form(
        action: "/watchlist/#{@alert.id}/toggle",
        method: "post",
        style: "display:inline"
      ) do
        input(type: "hidden", name: "_method", value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(
          type: "submit",
          title: @alert.active? ? "點擊停用" : "點擊啟用",
          class: status_button_class
        ) { plain(status_label) }
      end
    end
  end

  def render_actions
    td(class: "px-3 py-3 text-right") do
      div(class: "flex items-center justify-end gap-2") do
        a(
          href: "/watchlist/#{@alert.id}/edit",
          class: "text-xs px-2.5 py-1 rounded-md border border-gray-200 text-gray-500 hover:bg-gray-100 transition-colors"
        ) { plain("編輯") }

        form(
          action: "/watchlist/#{@alert.id}",
          method: "post",
          data: { confirm_delete: "確定刪除 #{@alert.symbol} 的通知嗎？" }
        ) do
          input(type: "hidden", name: "_method", value: "delete")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(
            type: "submit",
            class: "text-xs px-2.5 py-1 rounded-md border border-red-100 text-red-400 hover:bg-red-50 transition-colors"
          ) { plain("刪除") }
        end
      end
    end
  end

  def condition_label        = @presenter.condition_label
  def condition_button_class = @presenter.condition_button_class
  def status_label           = @presenter.status_label
  def status_button_class    = @presenter.status_button_class
end
