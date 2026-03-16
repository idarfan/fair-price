# frozen_string_literal: true

# 集中管理 Daily Momentum 的 VIX 判斷閾值。
# 修改此處即可同時影響：立場卡、風險提示、倉位建議、Controller 邏輯。
module MomentumThresholds
  VIX_AGGRESSIVE_MAX   = 16  # VIX < 16  → 激進買入（低波動）
  VIX_CONSERVATIVE_MAX = 22  # VIX ≤ 22  → 保守買入；> 22 → 持幣觀望
end
