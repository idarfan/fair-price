# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 到期日預估股價 → 到期損益（leaps-call-spread-spec P7）。
  #
  # 每口損益 = (min(max(預估價 − K_L, 0), K_S − K_L) − mid 淨成本) × 100，
  # 所以結果必定落在 −最大虧損 與 +最大獲利 之間；報酬率 = 損益 ÷ 實付淨成本。
  # 兩腳參數由區塊渲染時從 service 結果帶到頁面上，這裡只重算這一個公式、不抓 Barchart。
  module Payoff
    module_function

    # 預估價空白回 nil；任何參數不合法回 { error: }。
    def call(long_strike:, short_strike:, d_mid:, target_price:)
      return nil if target_price.to_s.strip.empty?

      # 預估價可以是 0（標的歸零，落在「低於 K_L」＝最大虧損）；兩腳參數仍須 > 0。
      # BigDecimal 會把 "NaN"／"Infinity" 解析成功，要另外擋（NaN 進 clamp 會丟例外）。
      target = decimal(target_price)
      return { error: "預估股價格式錯誤：#{target_price}" } if target.nil? || !target.finite? || target.negative?

      k_l, k_s, cost = [ long_strike, short_strike, d_mid ].map { |v| positive_decimal(v) }
      return { error: "價差參數不合法，請重新整理區塊" } unless valid_legs?(k_l, k_s, cost)

      result(target, k_l, k_s, cost)
    end

    def result(target, k_l, k_s, cost)
      intrinsic = (target - k_l).clamp(BigDecimal("0"), k_s - k_l)
      pnl = (intrinsic - cost) * CONTRACT_MULTIPLIER
      ratio = pnl / (cost * CONTRACT_MULTIPLIER)
      { pnl: pnl, return_ratio: ratio, tone: tone(pnl),
        display: { pnl: signed_money(pnl), pct: Format.pct(ratio) } }
    end

    def valid_legs?(k_l, k_s, cost)
      k_l && k_s && cost && k_s > k_l && cost < k_s - k_l
    end

    def tone(pnl)
      return :profit if pnl.positive?

      pnl.negative? ? :loss : :breakeven
    end

    def signed_money(value) = value.positive? ? "+#{Format.money(value)}" : Format.money(value)

    def positive_decimal(raw)
      value = decimal(raw)
      value&.positive? ? value : nil
    end

    def decimal(raw)
      BigDecimal(raw.to_s.strip)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
