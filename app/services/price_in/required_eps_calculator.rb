# frozen_string_literal: true

# 圖 A：固定股價，反推「這個價格正在要求公司賺到多少 EPS」。
#
#   required_eps = price / multiple
#
# 算式裡沒有時間，所以 fiscal_year_label 由 Form 層強制必填後一路帶到這裡——
# 「FY2028 賺到 7.45」和「FY2031 賺到 7.45」是完全不同的兩件事。
module PriceIn
  class RequiredEpsCalculator
    Row = Data.define(:multiple, :required_eps) do
      def formatted_eps = Formatter.money(required_eps)
      def formatted_multiple = format("%g 倍", multiple)
    end

    Result = Data.define(:price, :rows, :band_low, :band_high) do
      # 現有預測撐不撐得住：色帶落在哪些倍數的右側
      def band? = !band_low.nil? && !band_high.nil?
    end

    def self.call(...) = new(...).call

    def initialize(price:, multiples:, band_low: nil, band_high: nil)
      @price     = price.to_f
      @multiples = Array(multiples).map(&:to_f)
      @band_low  = band_low&.to_f
      @band_high = band_high&.to_f
    end

    def call
      Result.new(
        price:     @price,
        rows:      @multiples.map { |m| Row.new(multiple: m, required_eps: required_eps(m)) },
        band_low:  @band_low,
        band_high: @band_high
      )
    end

    # 反推所需 EPS。multiple 為 0 或 nil 時回傳 nil，不拋例外——
    # 使用者打字打到一半的中間狀態不該讓整頁爆掉。
    def required_eps(multiple)
      m = multiple.to_f
      return nil if m.zero?

      @price / m
    end

    # 隱含本益比，供圖 A 的參考卡片使用。eps 為 0 或 nil 時回傳 nil。
    def self.implied_multiple(price, eps)
      return nil if eps.nil? || eps.to_f.zero?

      price.to_f / eps.to_f
    end
  end
end
