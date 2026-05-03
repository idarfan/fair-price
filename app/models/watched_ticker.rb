# frozen_string_literal: true

class WatchedTicker < ApplicationRecord
  validates :ticker, presence: true, uniqueness: { case_sensitive: false }
  validates :added_at, presence: true

  before_validation :normalize_ticker, :set_added_at

  scope :active, -> { where(active: true) }

  private

  def normalize_ticker
    self.ticker = ticker.to_s.upcase.strip
  end

  def set_added_at
    self.added_at ||= Time.current
  end
end
