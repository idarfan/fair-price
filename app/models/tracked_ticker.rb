# frozen_string_literal: true

class TrackedTicker < ApplicationRecord
  has_many :option_snapshots, dependent: :destroy

  # 正規化必須在驗證「之前」。原本寫在 before_save，唯一性驗證因此比對的是
  # 未正規化的值——搭配 case_sensitive: true 會讓 "aapl" 通過驗證、存檔時
  # upcase 成 "AAPL" 再撞上唯一索引，變成 500 而不是驗證錯誤。
  before_validation { self.symbol = symbol&.upcase&.strip }

  validates :symbol, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  def min_dte     = config.fetch("min_dte", 7)
  def max_dte     = config.fetch("max_dte", 90)
  def strike_range = config.fetch("strike_range", 0.3)

  def last_snapshot_date
    option_snapshots.maximum(:snapshot_date)
  end
end
