# frozen_string_literal: true

class OwnershipSnapshot < ApplicationRecord
  has_many :ownership_holders, dependent: :destroy

  validates :ticker, :quarter, :snapshot_date, presence: true
  validates :quarter, uniqueness: { scope: :ticker }

  scope :for_ticker, ->(ticker) { where(ticker: ticker.upcase).order(:snapshot_date) }
end
