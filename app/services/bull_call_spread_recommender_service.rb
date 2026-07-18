# frozen_string_literal: true

# bcvs.md §功能流程 步驟3：選定 K1 後,系統計算並給出 K2 建議(三檔:保守/平衡/積極),
# 以 debit÷價差寬度 比值 r 從候選 K2 中選最接近目標值者。純計算層,不打 Barchart、
# 不寫 DB——候選 strikes 由呼叫端傳入(已由 BcvsCacheService 過濾掉 bid=0/OI=0)。
#
# Usage:
#   result = BullCallSpreadRecommenderService.new(
#     k1: 70.0, k1_ask: 8.00, candidates: chain_rows
#   ).call
#   result[:conservative][:k2]      # => 選中的 K2 履約價
#   result[:conservative][:result]  # => BullCallSpreadCalculatorService::Result
class BullCallSpreadRecommenderService
  TARGET_RATIOS = { conservative: 0.60, balanced: 0.50, aggressive: 0.35 }.freeze

  def initialize(k1:, k1_ask:, candidates:)
    @k1         = k1.to_f
    @k1_ask     = k1_ask.to_f
    @candidates = build_candidates(candidates)
  end

  def call
    remaining = @candidates.dup
    tabs = {}

    TARGET_RATIOS.each do |tab, target_r|
      break if remaining.empty?

      chosen = remaining.min_by { |c| (c[:r] - target_r).abs }
      remaining.delete(chosen)

      tabs[tab] = { k2: chosen[:strike], target_ratio: target_r, ratio: chosen[:r], result: chosen[:result] }
    end

    tabs
  end

  private

  # 候選 K2 = 鏈上所有 > K1 的履約價；bid 為 0 或 open interest 為 0 者剔除
  # （bcvs.md §功能流程 步驟3，即使 upstream 已過濾也在此防呆一次）。
  def build_candidates(rows)
    Array(rows).filter_map do |row|
      strike = (row["strike"] || row[:strike]).to_f
      bid    = (row["bid"] || row[:bid]).to_f
      ask    = (row["ask"] || row[:ask]).to_f
      oi     = (row["open_interest"] || row[:open_interest]).to_f

      next if strike <= @k1
      next if bid <= 0 || oi <= 0

      result = BullCallSpreadCalculatorService.new(k1: @k1, k1_ask: @k1_ask, k2: strike, k2_bid: bid).call
      next if result.warning == :invalid_width || result.max_loss.nil? || result.max_loss.zero?

      { strike: strike, r: (result.debit / result.width), result: result }
    end
  end
end
