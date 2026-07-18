# frozen_string_literal: true

class BcvsChainSnapshot < ApplicationRecord
  FRESH_WINDOW = 30.minutes

  validates :symbol, :expiration, :scraped_at, presence: true

  scope :for_symbol_and_expiration, ->(sym, exp) { where(symbol: sym.upcase, expiration: exp) }
  scope :fresh,                     -> { where(scraped_at: FRESH_WINDOW.ago..) }
end
