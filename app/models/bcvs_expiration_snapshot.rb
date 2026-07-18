# frozen_string_literal: true

class BcvsExpirationSnapshot < ApplicationRecord
  FRESH_WINDOW = 30.minutes

  validates :symbol, :scraped_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.upcase) }
  scope :fresh,      -> { where(scraped_at: FRESH_WINDOW.ago..) }
end
