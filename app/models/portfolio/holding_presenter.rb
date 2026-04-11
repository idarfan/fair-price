# frozen_string_literal: true

class Portfolio
  # Wraps a Portfolio holding + live quote and exposes calculated display values.
  # Keeps financial math out of the view component.
  class HoldingPresenter
    attr_reader :holding

    def initialize(holding:, quote: nil)
      @holding = holding
      @quote   = quote
    end

    def price
      @price ||= @quote&.dig("c")&.to_f
    end

    def price?
      price&.positive?
    end

    def market_value
      @market_value ||= price? ? price * @holding.shares : nil
    end

    def pnl_amount
      @pnl_amount ||= market_value ? market_value - @holding.total_cost : nil
    end

    def pnl_pct
      return nil unless pnl_amount && @holding.total_cost.positive?

      @pnl_pct ||= pnl_amount / @holding.total_cost * 100
    end

    def change_amount
      @quote&.dig("d")&.to_f
    end

    def change_pct
      @quote&.dig("dp")&.to_f
    end

    def fmt_shares
      val = @holding.shares
      val == val.floor ? val.to_i.to_s : sprintf("%.5g", val)
    end
  end
end
