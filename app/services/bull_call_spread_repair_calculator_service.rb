# frozen_string_literal: true

# bcvs.md §修復模式：使用者已持有 K1 長倉（如虧損中的 LEAPS）時填入實際進場
# 成本 basis，改用 basis 取代 K1 ask 計算鎖定結果，並提供「對照現在直接平倉」
# 三種到期情境。純計算層，不打 Barchart、不寫 DB。
#
# Usage:
#   result = BullCallSpreadRepairCalculatorService.new(
#     k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90, k1_current_bid: 2.10
#   ).call
#   result.locked_result   # => (K2-K1) + K2_bid - basis, per-share
#   result.warning          # => nil | :locked_loss
class BullCallSpreadRepairCalculatorService
  Result = Struct.new(
    :k1, :k2, :k2_bid, :basis,
    :locked_result, :locked_result_total, :breakeven_basis, :warning,
    :below_k1_pnl, :below_k1_pnl_total,
    :closeout_proceeds, :closeout_pnl,
    keyword_init: true
  )

  def initialize(k1:, k2:, k2_bid:, basis:, k1_current_bid: nil)
    @k1              = k1.to_f
    @k2              = k2.to_f
    @k2_bid          = k2_bid.to_f
    @basis           = basis.to_f
    @k1_current_bid  = k1_current_bid&.to_f
  end

  def call
    width           = (@k2 - @k1).round(4)
    breakeven_basis = (width + @k2_bid).round(4)

    # ≥K2 情境（兩腳皆到頂）：鎖定結果 = (K2−K1) + K2_bid − basis。
    locked_result = (width + @k2_bid - @basis).round(4)
    warning       = locked_result.negative? ? :locked_loss : nil

    # ≤K1 情境：兩腳皆歸零，只剩收到的 K2_bid 抵銷部分 basis。
    below_k1_pnl = (@k2_bid - @basis).round(4)

    Result.new(
      k1: @k1, k2: @k2, k2_bid: @k2_bid, basis: @basis,
      locked_result: locked_result, locked_result_total: (locked_result * 100).round(2),
      breakeven_basis: breakeven_basis, warning: warning,
      below_k1_pnl: below_k1_pnl, below_k1_pnl_total: (below_k1_pnl * 100).round(2),
      closeout_proceeds: closeout_proceeds, closeout_pnl: closeout_pnl
    )
  end

  # K1<價格<K2 情境的 P&L 是連續函數，非單一數字：mid_pnl(price) = (price−K1) + K2_bid − basis。
  # 提供給 View 端代入實際數字生成文案用（bcvs.md §修復模式「並以實際數字帶入」）。
  def mid_pnl(price)
    ((price.to_f - @k1) + @k2_bid - @basis).round(4)
  end

  private

  def closeout_proceeds
    return nil if @k1_current_bid.nil?
    (@k1_current_bid * 100).round(2)
  end

  def closeout_pnl
    return nil if @k1_current_bid.nil?
    ((@k1_current_bid - @basis) * 100).round(2)
  end
end
