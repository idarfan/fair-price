# frozen_string_literal: true

class IvDailySnapshot < ApplicationRecord
  validates :ticker,        presence: true
  validates :snapshot_date, presence: true
  validates :ticker,        uniqueness: { scope: :snapshot_date }

  scope :for_ticker, ->(t) { where(ticker: t.to_s.upcase.strip) }
  scope :ordered,    -> { order(snapshot_date: :asc) }
end
