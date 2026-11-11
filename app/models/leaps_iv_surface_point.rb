# frozen_string_literal: true

# LEAPS IV 曲面的原始點（leaps-iv-environment.md P1）：標的 × 美東交易日 × 到期日 × 履約價一列，
# 寫入一律 upsert（symbol, as_of_date, expiration, strike）。
class LeapsIvSurfacePoint < ApplicationRecord
  validates :symbol, :as_of_date, :expiration, :strike, :captured_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }
end
