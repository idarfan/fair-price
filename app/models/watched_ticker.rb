# frozen_string_literal: true

class WatchedTicker < ApplicationRecord
  # ticker 在 before_validation 已 upcase（見 normalize_ticker），DB 裡只有大寫。
  # 不用 case_sensitive: false——那會產生 LOWER() 查詢，用不到唯一索引。
  validates :ticker, presence: true, uniqueness: true
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
