# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 顯示用的文字與金額格式（只在顯示時四捨五入到 2 位，ROUND_HALF_UP）。
  # 數值本身在 LeapsVerticalSpreadService 內全程 BigDecimal，這裡只負責轉成字串。
  module Format
    AFTER_HOURS_NOTE = "（盤後參考價）"
    NO_QUOTE = "無報價"
    NO_NAT = "—（盤後無買賣價）"

    module_function

    def money(value)
      return nil if value.nil?

      ActiveSupport::NumberHelper.number_to_currency(value, unit: "$", precision: 2, round_mode: :half_up)
    end

    def num(value)
      ActiveSupport::NumberHelper.number_to_rounded(value, precision: 2, round_mode: :half_up)
    end

    # 算式用：兩位能精確表示就兩位，否則補到精確為止（最多 4 位），讓使用者照著算對得上。
    # 例：54.55 → "54.55"、12.975 → "12.975"、41.575 → "41.575"
    def exact(value)
      return nil if value.nil?

      v = BigDecimal(value.to_s)
      places = (2..4).find { |p| v == v.round(p) } || 4
      ActiveSupport::NumberHelper.number_to_rounded(v, precision: places, round_mode: :half_up)
    end

    # 比例 → 百分比字串（0.028508 → "+2.85%"）。signed: false 不加正號。
    def pct(ratio, signed: true)
      text = "#{num(ratio * 100)}%"
      signed && ratio.positive? ? "+#{text}" : text
    end

    # 2028-01-21 · 483 DTE｜100.00｜mid 53.50｜Δ 0.82
    def long_label(option)
      "#{option[:expiry][0, 10]} · #{option[:dte]} DTE｜#{num(option[:strike])}｜#{price_part(option)}｜#{delta_part(option[:delta])}"
    end

    # 210.00｜mid 11.20｜Δ 0.30 ／ 210.00｜last 11.20（盤後參考價）｜Δ 0.30 ／ 210.00｜無報價｜Δ 0.30
    def short_label(option)
      "#{num(option[:strike])}｜#{price_part(option)}｜#{delta_part(option[:delta])}"
    end

    def price_part(option)
      case option[:source]
      when :mid  then "mid #{num(option[:price])}"
      when :last then "last #{num(option[:price])}#{AFTER_HOURS_NOTE}"
      else NO_QUOTE
      end
    end

    def delta_part(delta) = delta.nil? ? "Δ —" : "Δ #{num(delta)}"

    def result(values)
      {
        width:        money(values[:width]),
        net_cost:     money(values[:net_cost]),
        net_cost_nat: values[:net_cost_nat].nil? ? NO_NAT : money(values[:net_cost_nat]),
        max_loss:     money(values[:max_loss]),
        max_profit:   money(values[:max_profit]),
        breakeven:    money(values[:breakeven]),
        risk_reward:  "1 : #{num(values[:risk_reward])}"
      }
    end
  end
end
