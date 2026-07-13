# frozen_string_literal: true

# BPUS §5：純計算層，不打 Barchart、不寫 DB。輸入兩腳的 strike/報價（保守計價：
# 賣方 bid、買方 ask，由呼叫端決定要傳哪個欄位進來，這裡不管報價來源），輸出
# §5 公式表全部欄位 + §6「什麼情況下賠錢」所需的原始數字，文案組裝留給 View。
#
# Usage:
#   result = BullPutSpreadCalculatorService.new(
#     short_strike: 75.0, short_bid: 3.20,
#     long_strike:  70.0, long_ask:  1.70
#   ).call
#   result.net_credit  # => 150.0
#   result.warning      # => nil | :debit | :invalid_width
class BullPutSpreadCalculatorService
  Result = Struct.new(
    :short_strike, :long_strike,
    :net_credit, :width, :max_profit, :max_loss, :margin,
    :breakeven, :roc, :risk_reward, :warning,
    keyword_init: true
  )

  def initialize(short_strike:, short_bid:, long_strike:, long_ask:)
    @short_strike = short_strike.to_f
    @short_bid    = short_bid.to_f
    @long_strike  = long_strike.to_f
    @long_ask     = long_ask.to_f
  end

  def call
    width = (@short_strike - @long_strike).round(4)
    return invalid_width_result(width) if width <= 0

    net_credit = ((@short_bid - @long_ask) * 100).round(2)
    max_risk   = (width * 100).round(2)
    max_loss   = (max_risk - net_credit).round(2)
    margin     = max_loss
    breakeven  = (@short_strike - net_credit / 100.0).round(4)

    # 淨權利金 ≤ 0 = debit 組合，非收租結構；仍顯示數字但不給 ROC / 風險報酬比。
    warning = net_credit <= 0 ? :debit : nil

    roc          = warning ? nil : percent_ratio(net_credit, margin, decimals: 1)
    risk_reward  = warning ? nil : ratio(max_loss, net_credit, decimals: 2)

    Result.new(
      short_strike: @short_strike,
      long_strike:  @long_strike,
      net_credit:   net_credit,
      width:        width,
      max_profit:   net_credit,
      max_loss:     max_loss,
      margin:       margin,
      breakeven:    breakeven,
      roc:          roc,
      risk_reward:  risk_reward,
      warning:      warning
    )
  end

  private

  # ROC = 淨權利金 ÷ 押金，一位小數的百分比（例如 15.3 代表 15.3%）。
  def percent_ratio(numerator, denominator, decimals:)
    return nil if denominator.nil? || denominator.zero?
    ((numerator / denominator.to_f) * 100).round(decimals)
  end

  # 風險報酬比「1 : X」裡的 X，兩位小數。
  def ratio(numerator, denominator, decimals:)
    return nil if denominator.nil? || denominator.zero?
    (numerator / denominator.to_f).round(decimals)
  end

  # width <= 0 代表 CSP 腳 strike 沒有真的高於保護腳——UI 端已限制不可選這種
  # 組合（spec §4 Step4），這裡是最後一道防呆，不假設呼叫端一定守規矩。
  def invalid_width_result(width)
    Result.new(
      short_strike: @short_strike, long_strike: @long_strike,
      net_credit: nil, width: width, max_profit: nil, max_loss: nil,
      margin: nil, breakeven: nil, roc: nil, risk_reward: nil,
      warning: :invalid_width
    )
  end
end
