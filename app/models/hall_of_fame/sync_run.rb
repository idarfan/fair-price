# frozen_string_literal: true

module HallOfFame
  # 每次同步的執行紀錄；http_validators 存條件式請求用的 ETag／Last-Modified（§1-10）。
  # kind 區分索引同步（index，只有它帶 validators）、PDF 解析（pdf_parse）與期權反推（options）。
  class SyncRun < ApplicationRecord
    KINDS = %w[index pdf_parse options].freeze

    validates :started_at, presence: true
    validates :source, inclusion: { in: Official::SOURCES }
    validates :kind, inclusion: { in: KINDS }
  end
end
