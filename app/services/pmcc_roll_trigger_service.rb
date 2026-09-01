# frozen_string_literal: true

# pmcc-tracker Phase 2：判斷「這一腳短腳該不該滾倉」。
#
# 純計算層——不打 Barchart、不寫 DB、**不自動執行滾倉**，只回傳觸發原因清單
# 讓使用者自己決定。這與本專案「列出全部候選、只標分級、不自動下結論」的
# 一貫原則一致（同 LEAPS 排行表只標流動性分級）。
#
#   PmccRollTriggerService.call(short_leg, quote: quote_row)
#   # => { should_roll: true, reasons: [{ code: :deep_itm, message: "…" }], evaluated: [...] }
class PmccRollTriggerService
  # 深度價內：時間價值近枯竭，繼續持有等於承擔被指派風險卻收不到多少租金
  DEEP_ITM_DELTA = 0.60

  # 近到期且接近/價內：Gamma 風險陡升、被指派機率跳增
  NEAR_EXPIRY_DTE  = 5
  NEAR_MONEY_FLOOR = -0.05   # moneyness 正=價內、負=價外（見 pmcc_short_call_snapshots）

  Reason = Struct.new(:code, :message, keyword_init: true)

  def self.call(short_leg, quote: nil, manual: false)
    new(short_leg, quote: quote, manual: manual).call
  end

  def initialize(short_leg, quote: nil, manual: false)
    @short_leg = short_leg
    @quote     = quote
    @manual    = manual
  end

  def call
    # 報價缺失時**不能回「不需滾倉」**——那會讓使用者以為系統看過了說沒事，
    # 實際上是根本沒資料可看。明確回報 :no_quote 讓畫面說得出「報價缺失」。
    return no_quote_result unless @manual || quote_usable?

    reasons = []
    reasons << deep_itm_reason
    reasons << near_expiry_reason
    reasons << manual_reason
    reasons = reasons.compact

    {
      should_roll: reasons.any?,
      reasons:     reasons,
      evaluated:   evaluated_snapshot
    }
  end

  private

  def quote_usable?
    @quote.present? && (delta.present? || (dte.present? && moneyness.present?))
  end

  def no_quote_result
    {
      should_roll: false,
      reasons:     [],
      evaluated:   evaluated_snapshot,
      error:       :no_quote
    }
  end

  def deep_itm_reason
    return nil if delta.blank? || delta < DEEP_ITM_DELTA

    Reason.new(
      code:    :deep_itm,
      message: "短腳 Delta #{format('%.2f', delta)} ≥ #{DEEP_ITM_DELTA}（深度價內，" \
               "時間價值近枯竭，繼續持有收不到多少租金卻仍承擔被指派風險）"
    )
  end

  def near_expiry_reason
    return nil if dte.blank? || moneyness.blank?
    return nil unless dte <= NEAR_EXPIRY_DTE && moneyness >= NEAR_MONEY_FLOOR

    Reason.new(
      code:    :near_expiry_at_money,
      message: "剩餘 #{dte} 天且 moneyness #{format('%+.1f%%', moneyness * 100)}" \
               "（接近或已在價內，Gamma 風險陡升、被指派機率跳增）"
    )
  end

  def manual_reason
    return nil unless @manual

    Reason.new(code: :manual, message: "使用者手動要求滾倉建議")
  end

  # 把判斷當下用到的數值一併回傳：畫面要能說明「依據什麼判斷」，
  # 而不是只丟一個布林值。
  def evaluated_snapshot
    { delta: delta, dte: dte, moneyness: moneyness }
  end

  def delta
    @delta ||= numeric(@quote, :delta)
  end

  def dte
    @dte ||= numeric(@quote, :dte)&.to_i
  end

  def moneyness
    @moneyness ||= numeric(@quote, :moneyness)
  end

  # quote 可能是 PmccShortCallSnapshot、Hash（symbol key）或 Hash（string key）
  def numeric(source, key)
    return nil if source.blank?

    raw = if source.respond_to?(key)      then source.public_send(key)
    elsif source.respond_to?(:[]) then source[key] || source[key.to_s]
    end
    raw&.to_f
  end
end
