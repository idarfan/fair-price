# frozen_string_literal: true

module HallOfFame
  # 一份公開申報（House PTR／年報／修正，OGE 278e／278-T）。(source, doc_id) 唯一。
  class Filing < ApplicationRecord
    FILING_TYPES   = %w[ptr annual amendment oge_278e oge_278t].freeze
    PARSE_STATUSES = %w[pending parsed needs_review failed].freeze

    belongs_to :official, class_name: "HallOfFame::Official"
    has_many :holdings, class_name: "HallOfFame::Holding", dependent: :destroy
    has_many :trades,   class_name: "HallOfFame::Trade",   dependent: :destroy

    validates :doc_id, presence: true
    validates :doc_id, uniqueness: { scope: :source }
    validates :source, inclusion: { in: Official::SOURCES }
    validates :filing_type, inclusion: { in: FILING_TYPES }
    validates :parse_status, inclusion: { in: PARSE_STATUSES }
  end
end
