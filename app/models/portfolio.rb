# frozen_string_literal: true

class Portfolio < ApplicationRecord
  validates :symbol,    presence: true,
                        format: { with: /\A[A-Za-z0-9.\-]{1,10}\z/, message: "格式不正確" }
  validates :shares,    numericality: { greater_than: 0 }
  validates :unit_cost, numericality: { greater_than: 0 }
  validates :sell_price, numericality: { greater_than: 0, allow_nil: true }

  before_validation { self.symbol = symbol&.upcase&.strip }

  scope :ordered, -> { order(:position, :created_at) }

  def self.next_position
    maximum(:position).to_i + 1
  end

  def total_cost
    shares * unit_cost
  end

  def profit_if_sold
    return nil unless sell_price
    (sell_price - unit_cost) * shares
  end
end
