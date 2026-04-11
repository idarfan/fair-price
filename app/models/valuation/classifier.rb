# frozen_string_literal: true

module Valuation
  # Determines stock type and estimates growth rate from market data.
  module Classifier
    private

    def classify
      sector   = @d[:sector].to_s
      industry = @d[:industry].to_s.downcase
      eps      = @d[:eps_ttm]

      return "REITs"    if sector == "Real Estate"
      return "公用事業" if sector == "Utilities"
      return "金融股"   if sector == "Financial Services"

      if [ "Energy", "Basic Materials" ].include?(sector) ||
         CYCLICAL_KEYWORDS.any? { |k| industry.include?(k) }
        return "週期股"
      end

      # Consumer Cyclical / Industrials 虧損 → 週期性低谷，非成長股
      return "週期股" if GROWTH_CYCLICAL_SECTORS.include?(sector) && eps && eps < 0

      # 真正的虧損成長股：成長型產業 + 實質營收成長 > 10%
      if eps && eps < 0
        rev_growth = @d[:revenue_growth].to_f
        return "虧損成長股" if GROWTH_SECTORS.any? { |s| sector.include?(s) } && rev_growth > 0.10

        return "一般股"
      end

      "一般股"
    end

    def growth_rate_sources
      @growth_rate_sources ||= begin
        sources = []
        sources << [ "盈餘成長(YoY)", @d[:earnings_growth] ]           if valid_growth?(@d[:earnings_growth])
        sources << [ "營收成長",       @d[:revenue_growth] ]            if valid_growth?(@d[:revenue_growth])
        sources << [ "季度盈餘成長",   @d[:earnings_quarterly_growth] ] if valid_growth?(@d[:earnings_quarterly_growth])

        if @d[:forward_eps] && @d[:eps_ttm]&.positive?
          fg = (@d[:forward_eps] - @d[:eps_ttm]) / @d[:eps_ttm]
          sources << [ "FwdEPS推算", fg ] if valid_growth?(fg)
        end

        sources
      end
    end

    def estimate_growth_rate
      sources = growth_rate_sources.map(&:last)
      return 0.10 if sources.empty?

      sorted = sources.sort
      sorted[sorted.length / 2].clamp(0.03, 0.45)
    end

    def valid_growth?(v)
      v&.between?(-0.5, 2.0)
    end
  end
end
