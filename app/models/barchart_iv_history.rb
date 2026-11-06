# frozen_string_literal: true

# Barchart Options Overview History 每日一列（leaps-iv-environment.md P1），Barchart IV 指標的唯一來源。
# IV Rank／Pctl 直接採用頁面值（0–100），不得自行重算；寫入一律 upsert（symbol, trade_date）。
class BarchartIvHistory < ApplicationRecord
  validates :symbol, :trade_date, :captured_at, :source_url, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }
end
