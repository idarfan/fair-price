# frozen_string_literal: true

# 短腳歷史：一個部位可有多筆，每次滾倉產生一筆新的，舊的標記為 rolled 並
# 用 rolled_to 指向新的那筆（roll 鏈）。
class PmccShortLeg < ApplicationRecord
  belongs_to :position, class_name: "PmccPosition", foreign_key: :pmcc_position_id,
             inverse_of: :short_legs

  # roll 鏈：這一腳滾去哪一腳 / 這一腳是從哪一腳滾來的
  belongs_to :rolled_to, class_name: "PmccShortLeg", optional: true
  has_one :rolled_from, class_name: "PmccShortLeg", foreign_key: :rolled_to_id,
          inverse_of: :rolled_to, dependent: :nullify

  VALID_STATUSES = %w[open expired_worthless rolled assigned].freeze

  validates :contracts,         numericality: { only_integer: true, greater_than: 0 }
  validates :short_strike,      numericality: { greater_than: 0 }
  validates :premium_collected, numericality: { greater_than_or_equal_to: 0 }
  validates :close_cost, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :short_expiration, :opened_at, presence: true
  validates :status, inclusion: { in: VALID_STATUSES }

  scope :open_legs,   -> { where(status: "open") }
  scope :closed_legs, -> { where.not(status: "open") }

  def open?
    status == "open"
  end

  # 賣出這一腳收到的權利金總額（每股 → 每口 ×100 ×口數）
  def premium_total
    premium_collected * contracts * 100
  end

  # 買回這一腳付出的成本總額；expired_worthless 沒有買回成本，視為 0
  def close_cost_total
    (close_cost || 0) * contracts * 100
  end
end
