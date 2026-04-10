# frozen_string_literal: true

class TrackedTicker < ApplicationRecord
  has_many :option_snapshots, dependent: :destroy

  validates :symbol, presence: true, uniqueness: { case_sensitive: false }

  before_save { self.symbol = symbol.upcase.strip }

  scope :active, -> { where(active: true) }

  def min_dte     = config.fetch("min_dte", 7)
  def max_dte     = config.fetch("max_dte", 90)
  def strike_range = config.fetch("strike_range", 0.3)

  def last_snapshot_date
    option_snapshots.maximum(:snapshot_date)
  end
end
