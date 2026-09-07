# frozen_string_literal: true

# 圖 B：固定未來 EPS，比較「同樣兌現這個盈利，不同買入價分到多少」。
#
#   target_price = eps * multiple
#   total_return = target_price / entry_price - 1
#   annualized   = (1 + total_return) ** (1 / years) - 1
#
# 這張圖存在的理由是打掉「公司成長 = 我會賺」的錯覺：同一列兩條長條的落差
# 就是買入價的代價。
module PriceIn
  class EntryReturnCalculator
    Cell = Data.define(:entry_price, :total_return, :annualized) do
      def formatted_return = Formatter.percent(total_return)
      def formatted_annualized = Formatter.percent(annualized)
    end

    Row = Data.define(:multiple, :target_price, :cells) do
      def formatted_target = Formatter.money(target_price)
      def formatted_multiple = format("%g 倍", multiple)
    end

    Result = Data.define(:eps, :rows, :entry_prices, :holding_years)

    def self.call(...) = new(...).call

    def initialize(eps:, multiples:, entry_prices:, holding_years: nil)
      @eps           = eps.to_f
      @multiples     = Array(multiples).map(&:to_f)
      @entry_prices  = Array(entry_prices).map(&:to_f)
      @holding_years = holding_years&.to_f
    end

    def call
      Result.new(
        eps:           @eps,
        rows:          @multiples.map { |m| build_row(m) },
        entry_prices:  @entry_prices,
        holding_years: @holding_years
      )
    end

    def self.target_price(eps, multiple) = eps.to_f * multiple.to_f

    def self.total_return(target_price, entry_price)
      return nil if entry_price.nil? || entry_price.to_f.zero?

      target_price.to_f / entry_price.to_f - 1
    end

    # 年化。holding_years 未填就不算——年化值錯得很隱蔽，寧可不顯示。
    def self.annualized(total_return, years)
      return nil if total_return.nil? || years.nil? || years.to_f <= 0

      (1 + total_return.to_f)**(1.0 / years.to_f) - 1
    end

    # 折現：把未來的目標價折回今天值多少
    def self.discounted_target(eps, multiple, rate, years)
      (eps.to_f * multiple.to_f) / ((1 + rate.to_f)**years.to_f)
    end

    # 反解：從今天的價格漲到未來目標價，隱含的年化報酬率是多少
    def self.implied_rate(target_future, price_today, years)
      return nil if price_today.nil? || price_today.to_f.zero? || years.nil? || years.to_f <= 0

      (target_future.to_f / price_today.to_f)**(1.0 / years.to_f) - 1
    end

    private

    def build_row(multiple)
      target = self.class.target_price(@eps, multiple)
      cells  = @entry_prices.map do |entry|
        total = self.class.total_return(target, entry)
        Cell.new(
          entry_price:  entry,
          total_return: total,
          annualized:   self.class.annualized(total, @holding_years)
        )
      end
      Row.new(multiple: multiple, target_price: target, cells: cells)
    end
  end
end
