# frozen_string_literal: true

class OwnershipSnapshot < ApplicationRecord
  SYMBOL_FORMAT = /\A[A-Z0-9.\-]{1,10}\z/

  before_validation { self.symbol = symbol&.upcase&.strip }

  validates :symbol,     presence: true, format: { with: SYMBOL_FORMAT }
  validates :fetched_at, presence: true

  scope :ordered, -> { order(fetched_at: :asc) }

  def self.history_for(sym, limit: 30)
    where(symbol: sym.upcase).order(fetched_at: :asc).last(limit)
  end

  def self.latest_for(sym)
    where(symbol: sym.upcase).order(fetched_at: :desc).first
  end
end
