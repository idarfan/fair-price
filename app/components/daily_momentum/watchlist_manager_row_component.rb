# frozen_string_literal: true

class DailyMomentum::WatchlistManagerRowComponent < ApplicationComponent
  # @param item  [WatchlistItem]  AR record
  # @param stock [Hash, nil]      Live quote data from MomentumReportService
  def initialize(item:, stock: nil)
    @item  = item
    @stock = stock
  end

  def view_template
    tr(
      id:    "wl-row-#{@item.id}",
      data:  { id: @item.id },
      class: "border-t border-gray-100 hover:bg-gray-50 transition-colors group"
    ) do
      render_drag_handle
      render_symbol_cell
      render_price_cell
      render_change_cell
      render_volume_cell
      render_range_cell
      render_actions_cell
    end
  end

  private

  def render_drag_handle
    td(class: "px-2 py-3 text-center") do
      span(class: "drag-handle cursor-grab active:cursor-grabbing text-gray-300 " \
                  "hover:text-gray-500 select-none text-lg leading-none") { plain("⠿") }
    end
  end

  def render_symbol_cell
    td(class: "px-4 py-3") do
      div(id: "view-#{@item.id}", class: "flex items-center gap-3") do
        div(class: "stock-logo-wrap flex-shrink-0 w-8 h-8 relative") do
          img(
            src:           "https://assets.parqet.com/logos/symbol/#{@item.symbol}?format=jpg",
            alt:           @item.symbol,
            class:         "stock-logo w-8 h-8 rounded-full object-contain border border-gray-100 bg-white",
            data_fallback: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/#{@item.symbol}.png",
            data_initials: @item.symbol.first(2)
          )
          span(
            class: "stock-logo-fallback w-8 h-8 rounded-full bg-gray-800 text-white text-xs font-bold items-center justify-center",
            style: "display:none"
          ) { plain(@item.symbol.first(2)) }
        end
        button(
          type:  "button",
          data:  { fetch_news: @item.symbol },
          title: "查看 #{@item.symbol} 相關新聞",
          class: "font-mono font-bold text-gray-900 hover:text-blue-600 transition-colors cursor-pointer"
        ) { plain(@item.symbol) }
        button(
          type:  "button",
          data:  { start_analysis: @item.symbol },
          title: "歐歐AI分析 #{@item.symbol}",
          class: "inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium " \
                 "bg-indigo-50 text-indigo-600 rounded-full border border-indigo-200 " \
                 "hover:bg-indigo-100 hover:border-indigo-400 transition-colors cursor-pointer"
        ) { plain("🐱 分析") }
      end
      form(
        id:     "edit-form-#{@item.id}",
        action: "/momentum/watchlist/#{@item.id}",
        method: "post",
        class:  "hidden flex gap-1 items-center"
      ) do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        input(
          type:      "text",
          name:      "symbol",
          value:     @item.symbol,
          maxlength: 10,
          class:     "w-24 px-2 py-1 text-xs border border-blue-300 rounded font-mono " \
                     "uppercase focus:outline-none focus:ring-1 focus:ring-blue-400"
        )
        button(type: "submit",
               class: "text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700") { plain("儲存") }
        button(type: "button",
               data: { cancel_edit: @item.id },
               class: "text-xs px-2 py-1 text-gray-500 hover:text-gray-700") { plain("取消") }
      end
    end
  end

  def render_price_cell
    td(class: "px-4 py-3 text-right") do
      span(class: "font-semibold text-gray-900") { plain(@stock ? fmt_currency(@stock[:price]) : "—") }
    end
  end

  def render_change_cell
    td(class: "px-4 py-3 text-right") { render_change }
  end

  def render_volume_cell
    td(class: "px-4 py-3 text-right text-gray-500 hidden md:table-cell") do
      plain(@stock&.dig(:volume) ? fmt_large(@stock[:volume].to_f) : "—")
    end
  end

  def render_range_cell
    td(class: "px-4 py-3 text-sm text-gray-500 hidden md:table-cell") { render_range }
  end

  def render_actions_cell
    td(class: "px-2 py-3") do
      div(class: "flex items-center justify-end gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity") do
        button(
          type:  "button",
          data:  { start_edit: @item.id },
          class: "p-1.5 text-gray-400 hover:text-blue-600 rounded transition-colors",
          title: "編輯"
        ) { plain("✏️") }

        form(action: "/momentum/watchlist/#{@item.id}", method: "post", class: "inline") do
          input(type: "hidden", name: "_method",            value: "delete")
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(
            type:  "submit",
            data:  { confirm: "確定刪除 #{@item.symbol}？" },
            class: "p-1.5 text-gray-400 hover:text-red-600 rounded transition-colors",
            title: "刪除"
          ) { plain("🗑️") }
        end
      end
    end
  end

  def render_change
    return span(class: "text-gray-400") { plain("—") } unless @stock&.dig(:change_pct)

    pct   = @stock[:change_pct]
    sign  = pct >= 0 ? "+" : ""
    color = change_color(pct)
    div do
      div(class: "font-medium #{color}") { plain("#{sign}#{sprintf('%.2f', pct * 100)}%") }
      if @stock[:change]
        csign = @stock[:change] >= 0 ? "+" : ""
        div(class: "text-xs #{color} opacity-75") { plain("#{csign}#{fmt_currency(@stock[:change])}") }
      end
    end
  end

  def render_range
    has_day = @stock && @stock[:day_high] && @stock[:day_low] && @stock[:day_high] > @stock[:day_low]
    has_52w = @stock && @stock[:high_52w] && @stock[:low_52w]

    return plain("—") unless has_day || has_52w

    price = @stock[:price]
    div(class: "min-w-44 text-xs text-gray-500 space-y-2") do
      if has_day
        render_range_bar("當日價格範圍", @stock[:day_low], @stock[:day_high], price,
                         "bg-red-400", "text-red-500")
      end
      if has_52w
        render_range_bar("52週範圍", @stock[:low_52w], @stock[:high_52w], price,
                         "bg-gray-400", "text-gray-500")
      end
    end
  end

  def render_range_bar(label, low, high, price, fill_class, marker_class)
    range = high - low
    pct   = range > 0 && price ? ((price - low) / range * 100).clamp(0, 100).round(1) : nil

    div do
      div(class: "text-center text-gray-400 mb-0.5") { plain(label) }
      div(class: "flex items-center gap-1.5") do
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(low)) }
        div(class: "relative flex-1 pb-2.5") do
          div(class: "h-1 bg-gray-200 rounded-full") do
            div(class: "h-full #{fill_class} rounded-full", style: "width:#{pct || 0}%")
          end
          if pct
            div(
              class: "absolute top-1.5 #{marker_class} leading-none",
              style: "left:calc(#{pct}% - 4px); font-size:8px"
            ) { plain("▲") }
          end
        end
        span(class: "shrink-0 tabular-nums") { plain(fmt_currency(high)) }
      end
    end
  end
end
