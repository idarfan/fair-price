# frozen_string_literal: true

class DailyMomentum::WatchlistManagerComponent < ApplicationComponent
  # @param items  [Array<WatchlistItem>]  AR records (ordered)
  # @param stocks [Array<Hash>]           Live quote data from MomentumReportService
  def initialize(items:, stocks:)
    @items  = items
    @stocks = stocks
  end

  def view_template
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      if @items.empty?
        render_empty_state
      else
        render_table
      end
    end
    render_scripts
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100 flex items-center justify-between") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("📋") }
        plain("觀察名單")
      end
      span(class: "text-xs text-gray-400 flex items-center gap-1") do
        span { plain("⠿") }
        plain("拖曳可調整順序")
      end
    end
  end

  def render_empty_state
    div(class: "px-5 py-8 text-center text-gray-400 text-sm") do
      plain("觀察名單為空，請使用上方搜尋框加入股票")
    end
  end

  def render_table
    div(class: "overflow-x-auto") do
      table(class: "w-full text-sm") do
        render_thead
        tbody(id: "watchlist-sortable") do
          @items.each do |item|
            stock = @stocks.find { |s| s[:symbol] == item.symbol }
            render DailyMomentum::WatchlistManagerRowComponent.new(item: item, stock: stock)
          end
        end
      end
    end
  end

  def render_thead
    thead(class: "bg-gray-50") do
      tr do
        th(class: "px-2 py-2.5 w-8")
        th(class: "px-4 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("股票") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("現價") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("漲跌") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide hidden md:table-cell") { plain("成交量") }
        th(class: "px-4 py-2.5 text-xs font-semibold text-gray-400 uppercase tracking-wide hidden md:table-cell") { plain("價格區間") }
        th(class: "px-2 py-2.5 w-16")
      end
    end
  end

  # JavaScript 已搬到 app/frontend/behaviors/momentumWatchlistManager.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_scripts
    div(data: { behavior: "momentum-watchlist-manager" })
  end
end
