# frozen_string_literal: true

module FairValue
  # Wraps an analyst consensus hash and exposes computed display values.
  # Extracts percentage calculations from AnalystConsensusComponent.
  class ConsensusPresenter
    RATING_STYLES = {
      "強力買入" => { bg: "bg-green-600",  text: "text-white",      badge: "bg-green-100 text-green-800" },
      "買入"     => { bg: "bg-green-400",  text: "text-white",      badge: "bg-green-50  text-green-700" },
      "持有"     => { bg: "bg-yellow-400", text: "text-gray-800",   badge: "bg-yellow-50 text-yellow-700" },
      "賣出"     => { bg: "bg-red-400",    text: "text-white",      badge: "bg-red-50    text-red-700" },
      "強力賣出" => { bg: "bg-red-600",    text: "text-white",      badge: "bg-red-100   text-red-800" }
    }.freeze

    def initialize(consensus)
      @consensus = consensus
    end

    def present?
      !@consensus.nil?
    end

    def rating
      @consensus[:rating]
    end

    def score
      @consensus[:score]
    end

    def total
      @consensus[:total]
    end

    def period
      @consensus[:period]
    end

    def style
      RATING_STYLES.fetch(rating, RATING_STYLES["持有"])
    end

    # Returns segments suitable for rendering the rating bar.
    # Each element: { label:, color:, pct: }
    def bar_segments
      return [] if total.to_f.zero?

      t = total.to_f
      [
        { count: @consensus[:strong_buy],  label: "強買", color: "bg-green-600" },
        { count: @consensus[:buy],         label: "買入", color: "bg-green-400" },
        { count: @consensus[:hold],        label: "持有", color: "bg-yellow-400" },
        { count: @consensus[:sell],        label: "賣出", color: "bg-red-400" },
        { count: @consensus[:strong_sell], label: "強賣", color: "bg-red-600" }
      ]
        .reject { |s| s[:count].zero? }
        .map    { |s| s.merge(pct: (s[:count] / t * 100).round(1)) }
    end

    # Returns rows suitable for rendering the breakdown table.
    # Each element: { label:, count:, color:, pct: }
    def breakdown_rows
      t = total.to_f
      [
        { label: "⬆⬆ 強力買入", key: :strong_buy,  color: "text-green-700 font-semibold" },
        { label: "⬆  買入",     key: :buy,         color: "text-green-600" },
        { label: "→  持有",     key: :hold,        color: "text-yellow-600" },
        { label: "⬇  賣出",     key: :sell,        color: "text-red-500" },
        { label: "⬇⬇ 強力賣出", key: :strong_sell, color: "text-red-700 font-semibold" }
      ].map do |row|
        count = @consensus[row[:key]]
        pct   = t > 0 ? (count / t * 100).round(0) : 0
        row.merge(count: count, pct: pct)
      end
    end
  end
end
