# frozen_string_literal: true

# LEAPS IV 環境的每日快照（leaps-iv-environment.md P1）。每標的每個美東交易日一筆，
# 寫入一律 upsert（symbol, as_of_date）；cm540_atm_iv 只由 LeapsIvEnvironmentService#persist! 寫入。
class LeapsIvSnapshot < ApplicationRecord
  SOURCES = %w[scheduled adhoc].freeze

  validates :symbol, :as_of_date, :source, :captured_at, :source_url, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }
end
