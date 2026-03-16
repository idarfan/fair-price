# frozen_string_literal: true

class DailyMomentum::WatchlistTableComponent < ApplicationComponent
  # @param stocks [Array<Hash>] Array of stock data hashes
  def initialize(stocks:)
    @stocks = stocks
  end

  def view_template
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "px-5 py-4 border-b border-gray-100") do
        h2(class: "font-semibold text-gray-900") do
          span(class: "mr-2") { plain("📋") }
          plain("觀察名單")
        end
      end
      if @stocks.empty?
        div(class: "px-5 py-8 text-center text-gray-400 text-sm") { plain("暫無資料") }
      else
        div(class: "overflow-x-auto") do
          table(class: "w-full text-sm") do
            render_header
            tbody do
              @stocks.each do |stock|
                render DailyMomentum::WatchlistRowComponent.new(
                  symbol:     stock[:symbol],
                  name:       stock[:name],
                  price:      stock[:price],
                  change:     stock[:change],
                  change_pct: stock[:change_pct],
                  volume:     stock[:volume],
                  day_high:   stock[:day_high],
                  day_low:    stock[:day_low],
                  high_52w:   stock[:high_52w],
                  low_52w:    stock[:low_52w]
                )
              end
            end
          end
        end
      end
    end
  end

  private

  def render_header
    thead(class: "bg-gray-50") do
      tr do
        th(class: "px-4 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("股票") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("現價") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("漲跌") }
        th(class: "px-4 py-2.5 text-right text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("成交量") }
        th(class: "px-4 py-2.5 text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("價格區間") }
      end
    end
  end
end
