# frozen_string_literal: true

class FairValue::AnalystConsensusComponent < ApplicationComponent
  RATING_STYLES = {
    "強力買入" => { bg: "bg-green-600",  text: "text-white",      badge: "bg-green-100 text-green-800" },
    "買入"     => { bg: "bg-green-400",  text: "text-white",      badge: "bg-green-50  text-green-700" },
    "持有"     => { bg: "bg-yellow-400", text: "text-gray-800",   badge: "bg-yellow-50 text-yellow-700" },
    "賣出"     => { bg: "bg-red-400",    text: "text-white",      badge: "bg-red-50    text-red-700" },
    "強力賣出" => { bg: "bg-red-600",    text: "text-white",      badge: "bg-red-100   text-red-800" }
  }.freeze

  # @param consensus [Hash, nil] analyst_consensus hash from StockDataService
  #   keys: strong_buy, buy, hold, sell, strong_sell, total, score, rating, period
  # @param symbol [String] Stock ticker for display
  # @param show_score [Boolean] Show numeric consensus score (1-5)
  # @param show_breakdown [Boolean] Show individual buy/hold/sell counts
  def initialize(consensus:, symbol: "", show_score: true, show_breakdown: true)
    @consensus      = consensus
    @symbol         = symbol
    @show_score     = show_score
    @show_breakdown = show_breakdown
  end

  def view_template
    if @consensus.nil?
      render_unavailable
    else
      render_consensus
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
    style = RATING_STYLES.fetch(@consensus[:rating], RATING_STYLES["持有"])

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      # Header
      div(class: "px-5 py-3.5 border-b border-gray-100 flex items-center justify-between") do
        div(class: "flex items-center gap-2") do
          span(class: "text-lg") { plain("📊") }
          span(class: "font-semibold text-gray-700 text-sm") { plain("華爾街分析師評級") }
        end
        if @consensus[:period]
          span(class: "text-xs text-gray-400") { plain("更新：#{@consensus[:period]}") }
        end
      end

      div(class: "px-5 py-4 space-y-4") do
        # Main rating + score row
        div(class: "flex items-center justify-between gap-4") do
          div(class: "flex items-center gap-3") do
            span(class: "text-2xl font-black #{style[:badge].split.first} #{style[:badge].split.last} px-4 py-1.5 rounded-lg") do
              plain(@consensus[:rating])
            end
            if @show_score
              div do
                p(class: "text-xs text-gray-400") { plain("綜合評分") }
                p(class: "text-xl font-bold text-gray-800") do
                  plain("#{@consensus[:score]}")
                  span(class: "text-sm text-gray-400 font-normal") { plain(" / 5.0") }
                end
              end
            end
          end
          div(class: "text-right") do
            p(class: "text-xs text-gray-400") { plain("覆蓋分析師") }
            p(class: "text-2xl font-bold text-gray-800") { plain("#{@consensus[:total]}") }
            p(class: "text-xs text-gray-400") { plain("位") }
          end
        end

        # Visual bar
        render_rating_bar(style)

        # Breakdown table
        render_breakdown if @show_breakdown
      end
    end
  end

  def render_rating_bar(style)
    total = @consensus[:total].to_f
    return if total.zero?

    segments = [
      { count: @consensus[:strong_buy],  label: "強買", color: "bg-green-600" },
      { count: @consensus[:buy],         label: "買入", color: "bg-green-400" },
      { count: @consensus[:hold],        label: "持有", color: "bg-yellow-400" },
      { count: @consensus[:sell],        label: "賣出", color: "bg-red-400" },
      { count: @consensus[:strong_sell], label: "強賣", color: "bg-red-600" }
    ].reject { |s| s[:count].zero? }

    div(class: "space-y-1") do
      div(class: "flex h-3 rounded-full overflow-hidden gap-0.5") do
        segments.each do |seg|
          pct = (seg[:count] / total * 100).round(1)
          div(class: "#{seg[:color]} rounded-sm", style: "width: #{pct}%",
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
    rows = [
      { label: "⬆⬆ 強力買入", count: @consensus[:strong_buy],  color: "text-green-700 font-semibold" },
      { label: "⬆  買入",     count: @consensus[:buy],         color: "text-green-600" },
      { label: "→  持有",     count: @consensus[:hold],        color: "text-yellow-600" },
      { label: "⬇  賣出",     count: @consensus[:sell],        color: "text-red-500" },
      { label: "⬇⬇ 強力賣出", count: @consensus[:strong_sell], color: "text-red-700 font-semibold" }
    ]

    total = @consensus[:total].to_f
    div(class: "grid grid-cols-2 gap-x-6 gap-y-1.5 pt-1 border-t border-gray-100") do
      rows.each do |row|
        next if row[:count].zero? && @consensus[:total] > 10

        pct = total > 0 ? (row[:count] / total * 100).round(0) : 0
        div(class: "flex items-center justify-between text-xs") do
          span(class: row[:color]) { plain(row[:label]) }
          span(class: "text-gray-500 tabular-nums") do
            plain("#{row[:count]} 位（#{pct}%）")
          end
        end
      end
    end
  end
end
