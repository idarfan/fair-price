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
    :s_star, :naked_cost, :naked_breakeven,
    :spread_max_value, :closeout_value, :closeout_profit, :realized_pct,
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
      risk_reward: risk_reward, warning: warning,
      s_star: s_star, naked_cost: naked_cost, naked_breakeven: naked_breakeven,
      spread_max_value: spread_max_value(width), closeout_value: closeout_value,
      closeout_profit: closeout_profit(cost), realized_pct: realized_pct(cost, max_profit)
    )
  end

  private

  # bcvs.md §為什麼不直接裸買：到期損益交叉價 S* = K2 ＋ K2 bid（短腳收到的
  # 權利金）。到期價 < S* 時價差策略勝出，> S* 時裸買勝出。
  def s_star
    (@k2 + @k2_bid).round(4)
  end

  def naked_cost
    (@k1_ask * 100).round(2)
  end

  def naked_breakeven
    (@k1 + @k1_ask).round(4)
  end

  def spread_max_value(width)
    (width * 100).round(2)
  end

  # bcvs.md §提前平倉指引：現值（毛額，「現在平倉可收回」）以快取 chain 保守
  # 估（K1 bid − K2 ask，賣出長腳、買回短腳的淨收回金額）。缺任一報價則回
  # nil，不得造值。
  def closeout_value
    return nil if @k1_bid.nil? || @k2_ask.nil?
    ((@k1_bid - @k2_ask) * 100).round(2)
  end

  # 淨額（「等於獲利/虧損」）＝現值−成本。兩個口徑必須並列顯示，不可混用
  # （bcvs.md §提前平倉指引「兩個口徑必須並列顯示、嚴禁混用」）。
  def closeout_profit(cost)
    value = closeout_value
    return nil if value.nil? || cost.nil?
    (value - cost).round(2)
  end

  # 判斷基準 Y＝已實現獲利比例＝(現值−成本)÷最大獲利，非現值佔最大價值的
  # 比例——bcvs.md 修訂版明講兩者不同，示範例（成本$194/收回上限$500/獲利
  # 上限$306，現值$250→獲利$56→Y≈18%）已用此公式反推驗證過。
  def realized_pct(cost, max_profit)
    profit = closeout_profit(cost)
    return nil if profit.nil? || max_profit.nil? || max_profit.zero?
    ((profit / max_profit) * 100).round(1)
  end

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
      warning: :invalid_width,
      s_star: nil, naked_cost: nil, naked_breakeven: nil,
      spread_max_value: nil, closeout_value: nil, closeout_profit: nil, realized_pct: nil
    )
  end
end
