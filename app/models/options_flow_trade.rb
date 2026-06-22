# frozen_string_literal: true

class OptionsFlowTrade < ApplicationRecord
  CANCELLED_CODES     = %w[CANC CNCL CNCO CNOL].freeze
  MULTI_LEG_CODES     = %w[MLET MLCT MLAT MLFT MESL CBMO MCTP].freeze
  STOCK_COMBO_CODES   = %w[TLET TLCT TLAT TLFT TESL].freeze
  INSTITUTIONAL_CODES = %w[SLFT MLFT TLFT].freeze
  TIMING_ANOMALY_CODES = %w[LATE OSEQ OPEN REOP].freeze

  validates :symbol, :snapshot_date, :fetched_at, presence: true

  scope :directional, -> {
    where(is_cancelled: false, is_multi_leg: false, is_stock_combo: false)
  }
  scope :for_symbol_date, ->(symbol, date) {
    where(symbol: symbol.upcase, snapshot_date: date)
  }
  scope :bullish_ask_calls, -> {
    directional.where(option_type: "Call", side: "ask", open_close: "BuyToOpen")
  }
  scope :bearish_ask_puts, -> {
    directional.where(option_type: "Put", side: "ask", open_close: "BuyToOpen")
  }
end
