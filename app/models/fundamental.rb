class Fundamental < ApplicationRecord
  validates :symbol, :snapshot_date, :fetched_at, presence: true
  validates :symbol, uniqueness: { scope: :snapshot_date }

  scope :latest_for, ->(symbol) {
    where(symbol: symbol.upcase).order(snapshot_date: :desc).first
  }

  def days_to_earnings
    return nil unless next_earnings_date
    (next_earnings_date - Date.today).to_i
  end

  def pre_earnings?
    d = days_to_earnings
    d && d >= 0 && d <= 7
  end
end
