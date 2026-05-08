# frozen_string_literal: true

class SkewRankDaily < ApplicationRecord
  self.table_name = "skew_rank_daily"

  scope :for_ticker, ->(t) { where(ticker: t.to_s.upcase) }
  scope :ordered,    -> { order(:snapshot_date) }
end
