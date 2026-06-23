# frozen_string_literal: true

# 根據 Section 2.3 規範，對單筆 Options Flow 交易進行方向 + 可信度分類。
#
# 核心原則（spec §2.3）：
#   - Code 只能判斷「排除」或「多腿/組合策略」，不用於判斷方向
#   - 方向判斷回到 Side + open_close（`*` 欄位）
#   - MLET 等多腿交易：單腿方向不可信 → INDETERMINATE
#   - ToOpen / N/A / mid：無法確認 buyer/seller → INDETERMINATE
#
# 用法：
#   trade = { "option_type" => "Call", "side" => "ask",
#             "open_close" => "BuyToOpen", "trade_condition" => "AUTO", ... }
#   OptionsFlowClassifierService.classify(trade)
#   # => { ..., "direction" => "bullish_directional", "is_cancelled" => false, ... }
#
#   OptionsFlowClassifierService.aggregate(trades)
#   # => { pure_directional: {...}, strategic: {...}, totals: {...} }
class OptionsFlowClassifierService
  # Direction constants
  BULLISH_DIRECTIONAL = "bullish_directional"   # Call ask BuyToOpen
  BULLISH_RENTAL      = "bullish_rental"         # Put  bid SellToOpen（賣 Put 收租）
  BEARISH_DIRECTIONAL = "bearish_directional"   # Put  ask BuyToOpen
  AMBIGUOUS_CALL_SELL = "ambiguous_call_sell"    # Call bid SellToOpen（Covered Call 或裸賣 Call，方向不明）
  INDETERMINATE       = "indeterminate"

  # open_close 值中，方向無法判斷的
  AMBIGUOUS_OPEN_CLOSE = [ "ToOpen", "N/A", "" ].freeze

  # large_premium 門檻：$500K（慣例值，源自第10課框架，尚無統計依據，待日後校正）
  LARGE_PREMIUM_THRESHOLD = 500_000

  # ─── Class-level entry points ────────────────────────────────────────────

  # 分類單筆交易，回傳加了 direction + 所有布林旗標的新 hash
  def self.classify(trade)
    new.classify(trade)
  end

  # 分類並彙總整批交易（回傳 pure_directional / strategic / totals）
  def self.aggregate(trades)
    new.aggregate(trades)
  end

  # ─── Instance methods ─────────────────────────────────────────────────────

  def classify(trade)
    code = trade["trade_condition"].to_s

    flags = {
      "is_cancelled"         => OptionsFlowTrade::CANCELLED_CODES.include?(code),
      "is_multi_leg"         => OptionsFlowTrade::MULTI_LEG_CODES.include?(code),
      "is_stock_combo"       => OptionsFlowTrade::STOCK_COMBO_CODES.include?(code),
      "urgency_high"         => code == "ISOI",
      "likely_institutional" => OptionsFlowTrade::INSTITUTIONAL_CODES.include?(code),
      "large_premium"        => trade["premium"].to_i >= LARGE_PREMIUM_THRESHOLD,
      "low_liquidity_period" => code == "EXHT",
      "timing_anomaly"       => OptionsFlowTrade::TIMING_ANOMALY_CODES.include?(code)
    }

    trade.merge(flags).merge("direction" => derive_direction(trade, flags))
  end

  def aggregate(trades)
    classified = trades.map { |t| classify(t) }

    active     = classified.reject { |t| t["is_cancelled"] }
    pure       = active.reject { |t| t["is_multi_leg"] || t["is_stock_combo"] }
    strategic  = active.select { |t| t["is_multi_leg"] || t["is_stock_combo"] }

    {
      pure_directional: pure_directional_stats(pure),
      strategic:        strategic_stats(strategic),
      totals: {
        total:                  classified.size,
        cancelled:              classified.count { |t| t["is_cancelled"] },
        multi_leg:              classified.count { |t| t["is_multi_leg"] },
        stock_combo:            classified.count { |t| t["is_stock_combo"] },
        urgency_high:           classified.count { |t| t["urgency_high"] },
        likely_institutional:   classified.count { |t| t["likely_institutional"] },
        large_premium:          classified.count { |t| t["large_premium"] },
        timing_anomaly:         classified.count { |t| t["timing_anomaly"] },
        pure_directional_count: pure.size,
        strategic_count:        strategic.size
      }
    }
  end

  private

  # ─── Direction derivation ─────────────────────────────────────────────────

  def derive_direction(trade, flags)
    return INDETERMINATE if flags["is_cancelled"]
    return INDETERMINATE if flags["is_multi_leg"] || flags["is_stock_combo"]

    type       = trade["option_type"].to_s   # "Call" | "Put"
    side       = trade["side"].to_s.downcase  # "ask" | "bid" | "mid"
    open_close = (trade["open_close"] || "").to_s.strip

    # mid 成交 = 方向未知；open_close 為 ToOpen/N/A/empty = 開倉方向不明
    return INDETERMINATE if side == "mid"
    return INDETERMINATE if AMBIGUOUS_OPEN_CLOSE.include?(open_close)

    case [ type, side, open_close ]
    in [ "Call", "ask", "BuyToOpen" ]  then BULLISH_DIRECTIONAL
    in [ "Put",  "bid", "SellToOpen" ] then BULLISH_RENTAL
    in [ "Put",  "ask", "BuyToOpen" ]  then BEARISH_DIRECTIONAL
    in [ "Call", "bid", "SellToOpen" ] then AMBIGUOUS_CALL_SELL
    else                                  INDETERMINATE
    end
  end

  # ─── Aggregate helpers ────────────────────────────────────────────────────

  def pure_directional_stats(trades)
    bto_calls  = trades.select { |t| t["direction"] == BULLISH_DIRECTIONAL }
    sto_puts   = trades.select { |t| t["direction"] == BULLISH_RENTAL }
    bto_puts   = trades.select { |t| t["direction"] == BEARISH_DIRECTIONAL }
    amb_calls  = trades.select { |t| t["direction"] == AMBIGUOUS_CALL_SELL }
    indet      = trades.select { |t| t["direction"] == INDETERMINATE }

    total_prem = premium_sum(trades)

    {
      pure_directional_premium_total:  total_prem,
      buyer_initiated_call_premium:    premium_sum(bto_calls),
      buyer_initiated_call_count:      bto_calls.size,
      seller_initiated_put_premium:    premium_sum(sto_puts),
      seller_initiated_put_count:      sto_puts.size,
      buyer_initiated_put_premium:     premium_sum(bto_puts),
      buyer_initiated_put_count:       bto_puts.size,
      ambiguous_call_sell_premium:     premium_sum(amb_calls),
      ambiguous_call_sell_count:       amb_calls.size,
      indeterminate_count:             indet.size,
      buyer_initiated_call_pct:        pct(premium_sum(bto_calls), total_prem),
      seller_initiated_put_pct:        pct(premium_sum(sto_puts),  total_prem),
      buyer_initiated_put_pct:         pct(premium_sum(bto_puts),  total_prem),
      ambiguous_call_sell_pct:         pct(premium_sum(amb_calls), total_prem),
      institutional_weighted_pct:      institutional_pct(trades, total_prem)
    }
  end

  def strategic_stats(trades)
    multi_leg   = trades.select { |t| t["is_multi_leg"] }
    stock_combo = trades.select { |t| t["is_stock_combo"] }
    total_prem  = premium_sum(trades)

    {
      strategic_premium_total:  total_prem,
      multi_leg_premium:        premium_sum(multi_leg),
      multi_leg_count:          multi_leg.size,
      stock_combo_premium:      premium_sum(stock_combo),
      stock_combo_count:        stock_combo.size,
      multi_leg_pct:            pct(premium_sum(multi_leg),   total_prem),
      stock_combo_pct:          pct(premium_sum(stock_combo), total_prem)
    }
  end

  def premium_sum(trades)
    trades.sum { |t| t["premium"].to_i }
  end

  def pct(numerator, total)
    return 0.0 if total.zero?
    (numerator.to_f / total * 100).round(1)
  end

  def institutional_pct(trades, total_prem)
    inst = trades.select { |t| t["likely_institutional"] }
    pct(premium_sum(inst), total_prem)
  end
end
