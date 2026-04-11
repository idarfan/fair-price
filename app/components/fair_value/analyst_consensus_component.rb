# frozen_string_literal: true

class FairValue::AnalystConsensusComponent < ApplicationComponent
  # @param consensus [Hash, nil] analyst_consensus hash from StockDataService
  #   keys: strong_buy, buy, hold, sell, strong_sell, total, score, rating, period
  # @param symbol [String] Stock ticker for display
  # @param show_score [Boolean] Show numeric consensus score (1-5)
  # @param show_breakdown [Boolean] Show individual buy/hold/sell counts
  def initialize(consensus:, symbol: "", show_score: true, show_breakdown: true)
    @presenter      = FairValue::ConsensusPresenter.new(consensus)
    @symbol         = symbol
    @show_score     = show_score
    @show_breakdown = show_breakdown
  end

  def view_template
    if @presenter.present?
      render_consensus
    else
      render_unavailable
    end
  end

  private

  def render_unavailable
    div(class: "bg-gray-50 rounded-xl border border-gray-200 p-4") do
      div(class: "flex items-center gap-2 text-gray-400") do
        span(class: "text-lg") { plain("📊") }
        div do
          p(class: "text-sm font-medium text-gray-500") { plain("分析師評級") }
          p(class: "text-xs") { plain("此股票暫無分析師評級資料") }
        end
      end
    end
  end

  def render_consensus
    style = @presenter.style

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      # Header
      div(class: "px-5 py-3.5 border-b border-gray-100 flex items-center justify-between") do
        div(class: "flex items-center gap-2") do
          span(class: "text-lg") { plain("📊") }
          span(class: "font-semibold text-gray-700 text-sm") { plain("華爾街分析師評級") }
        end
        if @presenter.period
          span(class: "text-xs text-gray-400") { plain("更新：#{@presenter.period}") }
        end
      end

      div(class: "px-5 py-4 space-y-4") do
        # Main rating + score row
        div(class: "flex items-center justify-between gap-4") do
          div(class: "flex items-center gap-3") do
            span(class: "text-2xl font-black #{style[:badge].split.first} #{style[:badge].split.last} px-4 py-1.5 rounded-lg") do
              plain(@presenter.rating)
            end
            if @show_score
              div do
                p(class: "text-xs text-gray-400") { plain("綜合評分") }
                p(class: "text-xl font-bold text-gray-800") do
                  plain("#{@presenter.score}")
                  span(class: "text-sm text-gray-400 font-normal") { plain(" / 5.0") }
                end
              end
            end
          end
          div(class: "text-right") do
            p(class: "text-xs text-gray-400") { plain("覆蓋分析師") }
            p(class: "text-2xl font-bold text-gray-800") { plain("#{@presenter.total}") }
            p(class: "text-xs text-gray-400") { plain("位") }
          end
        end

        # Visual bar
        render_rating_bar

        # Breakdown table
        render_breakdown if @show_breakdown
      end
    end
  end

  def render_rating_bar
    segments = @presenter.bar_segments
    return if segments.empty?

    div(class: "space-y-1") do
      div(class: "flex h-3 rounded-full overflow-hidden gap-0.5") do
        segments.each do |seg|
          div(class: "#{seg[:color]} rounded-sm", style: "width: #{seg[:pct]}%",
              title: "#{seg[:label]}: #{seg[:count]}")
        end
      end
      div(class: "flex justify-between text-xs text-gray-400") do
        span { plain("強力賣出") }
        span { plain("中立") }
        span { plain("強力買入") }
      end
    end
  end

  def render_breakdown
    div(class: "grid grid-cols-2 gap-x-6 gap-y-1.5 pt-1 border-t border-gray-100") do
      @presenter.breakdown_rows.each do |row|
        next if row[:count].zero? && @presenter.total > 10

        div(class: "flex items-center justify-between text-xs") do
          span(class: row[:color]) { plain(row[:label]) }
          span(class: "text-gray-500 tabular-nums") do
            plain("#{row[:count]} 位（#{row[:pct]}%）")
          end
        end
      end
    end
  end
end
