class FetchLog < ApplicationRecord
  STATUSES = %w[success barchart_session_expired dom_structure_changed error].freeze
  FETCH_TYPES = %w[technical fundamental options_flow max_pain].freeze

  validates :symbol, :fetch_type, :status, :fetched_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :fetch_type, inclusion: { in: FETCH_TYPES }

  scope :recent_failures, -> {
    where.not(status: "success").order(fetched_at: :desc).limit(50)
  }
end
