# frozen_string_literal: true

# 用使用者當前填的數字，演一次「需要的 EPS 對照預測區間」。
#
# 存在的理由是一個具體的誤判：把「現價 ÷ TTM EPS」算出來的倍數填回去當假設，
# 需要的 EPS 必然等於 TTM EPS，因為那只是把除法倒推回去。此時拿它跟明年的
# 預測比，「需要 3.03、預測 3.92」看起來很安全，但它只證明了分析師預期明年
# 比去年賺得多——任何成長中的公司都會通過這個測試，包括泡沫頂點的那些。
#
# 因此這裡除了算數字，還要主動把那一列標記為無效。
module PriceIn
  class LogicExampleBuilder
    # 現價反推倍數的判定容差。使用者填 73.8 而實際是 73.79 仍算同一件事。
    CIRCULAR_TOLERANCE = 0.02

    def self.call(...) = new(...).call

    # implied_current 是「現價 ÷ TTM EPS」。有值才做循環論證判定；
    # 沒抓到報價時寧可不標記，也不要把使用者自己判斷的倍數誤標成無效。
    def initialize(price:, multiples:, band_low: nil, band_high: nil,
                   fiscal_year_label: nil, implied_current: nil)
      @price           = price.to_f
      @multiples       = Array(multiples).map(&:to_f).sort.reverse
      @band_low        = band_low&.to_f
      @band_high       = band_high&.to_f
      @year            = fiscal_year_label
      @implied_current = implied_current&.to_f
    end

    def call
      return nil if @price <= 0 || @multiples.empty?

      { rows: @multiples.map { |m| build_row(m) }, footnote: footnote }
    end

    private

    def build_row(multiple)
      required = @price / multiple
      circular = circular?(multiple)

      {
        multiple:     Kernel.format("%g 倍", multiple),
        required_eps: Formatter.money(required),
        circular:     circular,
        verdict:      circular ? circular_verdict : verdict_for(required)
      }
    end

    # 使用者填的倍數是不是就是現價反推出來的那一個。
    def circular?(multiple)
      return false if @implied_current.nil? || @implied_current <= 0

      (multiple - @implied_current).abs <= @implied_current * CIRCULAR_TOLERANCE
    end

    def circular_verdict
      "這是現價反推出來的倍數。用它算回去必然得到目前的 EPS，" \
        "這個比較是循環論證，不能用來判斷貴或便宜。"
    end

    def verdict_for(required)
      return "填入 EPS 預測區間後，這裡會給出判讀。" unless band?

      if required < @band_low
        "低於預測下限#{year_suffix}，現有預測撐得住這個倍數。"
      elsif required > @band_high
        "高於預測上限#{year_suffix}，需要盈利超出目前所有預測——這個倍數是額外的樂觀。"
      else
        "落在預測區間之中#{year_suffix}，需要偏上緣，有機會但不寬裕。"
      end
    end

    def band? = !@band_low.nil? && !@band_high.nil?

    def year_suffix = @year.present? ? "（#{@year}）" : ""

    def footnote
      return "填入 EPS 預測區間後，每一列會標出現有預測撐不撐得住。" unless band?

      implied_low  = @band_high&.positive? ? @price / @band_high : nil
      implied_high = @band_low&.positive?  ? @price / @band_low  : nil
      return "" if implied_low.nil? || implied_high.nil?

      "反過來看：現價 #{Formatter.money(@price)} 除以預測區間兩端，" \
        "等於你正在付 #{Formatter.multiple(implied_low)} 到 #{Formatter.multiple(implied_high)} 的" \
        "#{@year.presence || '該年度'}盈利。這個方向不需要你先給倍數，因此沒有循環論證的問題。"
    end
  end
end
