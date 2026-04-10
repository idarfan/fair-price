# frozen_string_literal: true

class OptionSnapshot < ApplicationRecord
  belongs_to :tracked_ticker

  validates :snapshot_date, :contract_symbol, :option_type, :expiration, :strike, presence: true
  validates :option_type, inclusion: { in: %w[call put] }

  scope :puts,           -> { where(option_type: "put") }
  scope :calls,          -> { where(option_type: "call") }
  scope :for_expiration, ->(date) { where(expiration: date) }
  scope :recent_days,    ->(n = 60) { where("snapshot_date >= ?", n.days.ago.to_date) }
  scope :near_strike,    ->(price, range: 0.1) {
    where("strike BETWEEN ? AND ?", price * (1 - range), price * (1 + range))
  }

  def self.premium_trend(ticker_id:, strike:, expiration:, option_type: "put")
    where(
      tracked_ticker_id: ticker_id,
      strike:            strike,
      expiration:        expiration,
      option_type:       option_type
    ).order(:snapped_at)
  end
end
