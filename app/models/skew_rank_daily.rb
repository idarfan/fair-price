# frozen_string_literal: true

class SkewRankDaily < ApplicationRecord
  self.table_name = "skew_rank_daily"

  # DB 是 NOT NULL，補上對應的 model 驗證（NullConstraintChecker）。
  validates :ticker, :snapshot_date, presence: true

  scope :for_ticker, ->(t) { where(ticker: t.to_s.upcase) }
  scope :ordered,    -> { order(:snapshot_date) }
end
