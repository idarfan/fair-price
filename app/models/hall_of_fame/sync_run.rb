# frozen_string_literal: true

module HallOfFame
  # 每次同步的執行紀錄；http_validators 存條件式請求用的 ETag／Last-Modified（§1-10）。
  class SyncRun < ApplicationRecord
    validates :started_at, presence: true
    validates :source, inclusion: { in: Official::SOURCES }
  end
end
