# frozen_string_literal: true

class SkewRankIntraday < ApplicationRecord
  scope :for_ticker, ->(t) { where(ticker: t) }
  scope :ordered,    -> { order(:snapshot_time) }
  scope :since,      ->(t) { where("snapshot_time >= ?", t) }

  # Round snapshot_time down to nearest 30-minute slot before inserting
  before_validation :round_snapshot_time

  private

  def round_snapshot_time
    return unless snapshot_time
    mins = (snapshot_time.min / 30) * 30
    self.snapshot_time = snapshot_time.change(min: mins, sec: 0)
  end
end
