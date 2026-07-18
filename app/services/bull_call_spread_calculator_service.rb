# frozen_string_literal: true

# bcvs.md §策略定義：純計算層，不打 Barchart、不寫 DB。輸入兩腳的 strike/報價
# （保守計價：K1 取 ask、K2 取 bid，由呼叫端決定要傳哪個欄位進來），輸出策略
# 定義表格全部欄位。debit spread（K1 買、K2 賣），跟 BullPutSpreadCalculatorService
# 的 credit spread 公式方向相反，不可互相套用。
#
# Usage:
#   result = BullCallSpreadCalculatorService.new(
#     k1: 70.0, k1_ask: 8.00,
#     k2: 80.0, k2_bid: 4.10
#   ).call
#   result.debit       # => 3.90
#   result.max_profit   # => 610.0
class BullCallSpreadCalculatorService
  Result = Struct.new(
    :k1, :k2,
    :debit, :debit_mid, :width, :cost_per_contract,
    :max_profit, :max_loss, :breakeven, :risk_reward, :warning,
    keyword_init: true
  )

  def initialize(k1:, k1_ask:, k2:, k2_bid:, k1_bid: nil, k2_ask: nil)
    @k1     = k1.to_f
    @k1_ask = k1_ask.to_f
    @k2     = k2.to_f
    @k2_bid = k2_bid.to_f
    @k1_bid = k1_bid&.to_f
    @k2_ask = k2_ask&.to_f
  end

  def call
    width = (@k2 - @k1).round(4)
    return invalid_width_result(width) if width <= 0

    debit      = (@k1_ask - @k2_bid).round(2)
    cost       = (debit * 100).round(2)
    max_profit = ((@k2 - @k1 - debit) * 100).round(2)
    max_loss   = cost
    breakeven  = (@k1 + debit).round(4)

    # debit ≤ 0：淨收入而非淨支出，非典型 debit spread 結構（罕見，通常代表報價
    # 異常或倒掛），仍顯示數字但不給報酬風險比，避免除以非正數。
    warning = debit <= 0 ? :non_debit : nil
    risk_reward = warning ? nil : ratio(max_profit, max_loss, decimals: 2)

    Result.new(
      k1: @k1, k2: @k2,
      debit: debit, debit_mid: mid_debit, width: width, cost_per_contract: cost,
      max_profit: max_profit, max_loss: max_loss, breakeven: breakeven,
      risk_reward: risk_reward, warning: warning
    )
  end

  private

  # 另示 mid 供參（bcvs.md §策略定義：「另示 mid 供參」），需要雙腳的 bid/ask
  # 才能算 mid−mid，缺任一則回 nil，不得造值。
  def mid_debit
    return nil if @k1_bid.nil? || @k2_ask.nil?

    k1_mid = (@k1_ask + @k1_bid) / 2.0
    k2_mid = (@k2_bid + @k2_ask) / 2.0
    (k1_mid - k2_mid).round(2)
  end

  def ratio(numerator, denominator, decimals:)
    return nil if denominator.nil? || denominator.zero?
    (numerator / denominator.to_f).round(decimals)
  end

  # width <= 0 代表 K2 沒有真的高於 K1——UI 端已限制不可選這種組合，這裡是最後
  # 一道防呆，不假設呼叫端一定守規矩（比照 BullPutSpreadCalculatorService）。
  def invalid_width_result(width)
    Result.new(
      k1: @k1, k2: @k2,
      debit: nil, debit_mid: nil, width: width, cost_per_contract: nil,
      max_profit: nil, max_loss: nil, breakeven: nil, risk_reward: nil,
      warning: :invalid_width
    )
  end
end
