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
    def long_label(option) = long_segments(option).map(&:first).join

    # 210.00｜mid 11.20｜Δ 0.30 ／ 210.00｜last 11.20（盤後參考價）｜Δ 0.30 ／ 210.00｜無報價｜Δ 0.30
    def short_label(option) = short_segments(option).map(&:first).join

    # 下拉選項分段上色用：[[文字, tone]]，tone 為 nil 的只有純分隔符號（淡灰）；
    # 有資訊的文字（含「無報價」「（盤後參考價）」→ :note）都要帶 tone。顏色見 application.css 的 .vs-opt-*。
    def long_segments(option)
      [ [ option[:expiry][0, 10], :date ], [ " · ", nil ], [ "#{option[:dte]} DTE", :dte ], [ "｜", nil ],
        *short_segments(option) ]
    end

    def short_segments(option)
      [ [ num(option[:strike]), :strike ], [ "｜", nil ], *price_segments(option), [ "｜", nil ],
        [ delta_part(option[:delta]), :delta ] ]
    end

    def price_segments(option)
      case option[:source]
      when :mid  then [ [ "mid #{num(option[:price])}", :price ] ]
      when :last then [ [ "last #{num(option[:price])}", :price ], [ AFTER_HOURS_NOTE, :note ] ]
      else [ [ NO_QUOTE, :note ] ]
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

    # 反推 IV（小數）→ "IV 60.9%"（S3 第 6 點：小數一位）。
    def iv(value) = "IV #{ActiveSupport::NumberHelper.number_to_rounded(value * 100, precision: 1, round_mode: :half_up)}%"

    CARD_KEYS = %i[net_cost max_profit max_loss breakeven risk_reward].freeze

    # 五張指標卡的 mid／保守顯示值（tasks/leaps-vertical-fix.md S3 第 1 點），含口數與費用。
    # 沒有保守基準（有一腳用盤後參考價）時每格都顯示 NO_NAT。
    def cards(metrics)
      mid, nat = metrics.values_at(:mid, :conservative)
      CARD_KEYS.index_with do |key|
        { mid: card_value(mid, key), conservative: nat ? card_value(nat, key) : NO_NAT }
      end
    end

    def card_value(basis, key)
      return money(basis[key]) unless key == :risk_reward

      basis[:risk_reward].nil? ? "—" : "1 : #{num(basis[:risk_reward])}"
    end
  end
end
