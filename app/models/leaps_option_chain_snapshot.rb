# frozen_string_literal: true

class LeapsOptionChainSnapshot < ApplicationRecord
  validates :symbol, :expiration_date, :strike, :option_type, :scraped_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.upcase) }
  scope :calls,      -> { where(option_type: "Call") }
  scope :fresh,      -> { where(scraped_at: 5.minutes.ago..) }

  def mid_price
    return nil if bid.nil? && ask.nil?
    return ask if bid.nil?
    return bid if ask.nil?
    (bid + ask) / 2.0
  end
end
