class OptionsFlow < ApplicationRecord
  validates :symbol, :snapshot_date, :fetched_at, presence: true
  validates :symbol, uniqueness: { scope: :snapshot_date }

  scope :latest_for, ->(symbol) {
    where(symbol: symbol.upcase).order(snapshot_date: :desc).first
  }
end
