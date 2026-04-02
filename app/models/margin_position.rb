# frozen_string_literal: true

class MarginPosition < ApplicationRecord
  VALID_STATUSES = %w[open closed].freeze
  SYMBOL_FORMAT  = /\A[A-Za-z0-9.\-]{1,10}\z/

  before_validation { self.symbol = symbol&.upcase&.strip }

  validates :symbol,    presence: true, format: { with: SYMBOL_FORMAT }
  validates :buy_price, presence: true, numericality: { greater_than: 0 }
  validates :shares,    presence: true, numericality: { greater_than: 0 }
  validates :sell_price, numericality: { greater_than: 0, allow_nil: true }
  validates :opened_on, presence: true
  validates :status,    inclusion: { in: VALID_STATUSES }

  scope :open_positions,   -> { where(status: "open").order(:position, :opened_on) }
  scope :closed_positions, -> { where(status: "closed").order(closed_on: :desc) }

  def open?
    status == "open"
  end

  def balance
    buy_price.to_f * shares.to_f
  end
end
