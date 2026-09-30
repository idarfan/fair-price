# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 雙基準指標（tasks/leaps-vertical-fix.md S1、S1-b）。
  #
  # 同一組公式分別代入兩種每股淨成本 d：
  # - mid 基準：LC 價 − SC 價（價取 service `priced` 的 price；沒有就用 (bid + ask) ÷ 2）
  # - 保守基準：LC ask − SC bid（任一腳缺 bid／ask 時沒有這個基準）
  #
  # 金額 = 每股 × 100 × 口數；開倉費用 = 費率 × 2 腳 × 口數，平倉費用相同。
  # 最大虧損 = 淨成本 + 開倉費用（到期作廢不需平倉）；最大獲利 = 寬度金額 − 淨成本 − 來回費用；
  # 兩平 = K_L + d + 來回費用 ÷ (100 × 口數)。數值全程 BigDecimal，只在顯示時四捨五入。
  module Metrics
    module_function

    # long／short：{ strike:, bid:, ask:, price: }。target_price 為 nil 時不算到期損益。
    def dual(long:, short:, contracts:, fee_per_leg:, target_price: nil)
      args = { long_strike: long[:strike], short_strike: short[:strike], contracts: contracts,
               fee_per_leg: fee_per_leg, target_price: target_price }
      mid_cost = leg_price(long) && leg_price(short) && leg_price(long) - leg_price(short)
      nat_cost = conservative_cost(long, short)
      conservative = nat_cost && call(d: nat_cost, **args)
      { mid: mid_cost && call(d: mid_cost, **args), conservative: conservative,
        no_profit_room: conservative&.dig(:no_profit_room) }
    end

    def call(long_strike:, short_strike:, d:, contracts:, fee_per_leg:, target_price: nil)
      scale = CONTRACT_MULTIPLIER * contracts
      width = short_strike - long_strike
      open_fee = fee_per_leg * 2 * contracts
      net_cost = d * scale
      max_loss = net_cost + open_fee
      max_profit = width * scale - net_cost - open_fee * 2
      {
        d: d, net_cost: net_cost, max_loss: max_loss, max_profit: max_profit,
        breakeven: long_strike + d + open_fee * 2 / scale,
        risk_reward: max_loss.positive? ? max_profit / max_loss : nil,
        no_profit_room: d >= width,
        payoff: target_price && payoff(target_price, long_strike, width, net_cost, open_fee, scale, max_loss)
      }
    end

    # 到期損益：價內部分要平倉（扣來回費用），到期作廢只扣開倉費用；報酬率 = 損益 ÷ 實付（最大虧損）。
    def payoff(target, long_strike, width, net_cost, open_fee, scale, max_loss)
      intrinsic = (target - long_strike).clamp(BigDecimal("0"), width)
      close_fee = intrinsic.positive? ? open_fee : 0
      pnl = intrinsic * scale - net_cost - open_fee - close_fee
      { pnl: pnl, return_ratio: max_loss.positive? ? pnl / max_loss : nil }
    end

    def leg_price(leg)
      leg[:price] || (leg[:bid] && leg[:ask] && (leg[:bid] + leg[:ask]) / 2)
    end

    def conservative_cost(long, short)
      long[:ask] && short[:bid] && long[:bid] && short[:ask] ? long[:ask] - short[:bid] : nil
    end
  end
end
