# frozen_string_literal: true

# 一組 PMCC 部位 = 一筆長腳（LEAPS Call，深度價內、長期不動）
# + 多筆短腳歷史（每次滾倉產生一筆新的）。
#
# 持倉綁 user：真正的理由是**寫入隔離**——Phase 5 的建部位／滾倉／平倉表單
# 若不 scope，其他已登入帳號能新增假部位、把持倉標成已平倉、寫進損益帳本，
# 事後也查不出是誰做的。所有進入點一律從 current_user 出發
# （比照 Api::V1::MarginPositionsController：別人的 id 直接 RecordNotFound）。
#
# 短腳與帳本不另外掛 user_id，透過 position 關聯間接綁定。
class PmccPosition < ApplicationRecord
  belongs_to :user

  has_many :short_legs, class_name: "PmccShortLeg", dependent: :destroy,
           foreign_key: :pmcc_position_id, inverse_of: :position
  has_many :pnl_events, class_name: "PmccPnlEvent", dependent: :destroy,
           foreign_key: :pmcc_position_id, inverse_of: :position

  VALID_STATUSES = %w[active closed].freeze
  SYMBOL_FORMAT  = /\A[A-Za-z0-9.\-]{1,10}\z/

  before_validation { self.ticker = ticker&.upcase&.strip }

  validates :ticker, presence: true, format: { with: SYMBOL_FORMAT }
  validates :long_contracts,  numericality: { only_integer: true, greater_than: 0 }
  validates :long_strike,     numericality: { greater_than: 0 }
  validates :long_entry_cost, numericality: { greater_than: 0 }
  validates :long_expiration, :long_entry_date, presence: true
  validates :status, inclusion: { in: VALID_STATUSES }

  scope :active_positions, -> { where(status: "active") }
  scope :for_symbol,       ->(sym) { where(ticker: sym.to_s.upcase) }

  def active?
    status == "active"
  end

  # 目前這一腳短腳（同時只會有一筆 open）
  def open_short_leg
    short_legs.find_by(status: "open")
  end

  # 累積已實現損益：只加總帳本裡的真實現金流，不含任何估算值。
  def realized_pnl
    pnl_events.sum(:realized_pnl)
  end

  # 長腳投入成本（每股 → 每口 ×100 ×口數）
  def long_cost_basis
    long_entry_cost * long_contracts * 100
  end

  # 目前實際投入資本：滾倉收租會持續降低它。年化報酬率用這個當分母，
  # 用原始成本會低估報酬（見 pmcc-tracker.md Phase 4）。
  def capital_deployed
    long_cost_basis - realized_pnl
  end
end
