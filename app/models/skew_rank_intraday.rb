# frozen_string_literal: true

class SkewRankIntraday < ApplicationRecord
  # DB 是 NOT NULL，補上對應的 model 驗證（NullConstraintChecker）。
  # 註：本表由 SkewIntradaySnapshotService 走 upsert 寫入，該路徑跳過驗證；
  # 但 presence 驗證不產生額外查詢，留著能表達意圖也擋住直接 .create 的呼叫。
  validates :ticker, :snapshot_time, presence: true

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
