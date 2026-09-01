# frozen_string_literal: true

# 損益帳本：每次短腳了結或長腳異動各產生一筆。
#
# realized_pnl **只記真實現金流**（已扣手續費），不得寫入任何估算值——
# 帳本的價值在於可稽核，混進估算之後 SUM(realized_pnl) 就跟券商對帳單
# 永遠對不起來。長腳因短腳被指派而行權/平倉，另開一筆事件記它自己的實際成交。
class PmccPnlEvent < ApplicationRecord
  belongs_to :position, class_name: "PmccPosition", foreign_key: :pmcc_position_id,
             inverse_of: :pnl_events

  EVENT_TYPES = %w[
    short_expired short_closed short_assigned long_exercised long_closed
  ].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :realized_pnl, presence: true, numericality: true
  validates :fees, numericality: { greater_than_or_equal_to: 0 }
  validates :occurred_at, presence: true

  scope :chronological, -> { order(:occurred_at) }
end
