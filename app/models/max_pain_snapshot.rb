# frozen_string_literal: true

class MaxPainSnapshot < ApplicationRecord
  validates :symbol, :snapshot_date, :fetched_at, :expiration, presence: true
  validates :symbol, uniqueness: {
    scope: [:snapshot_date, :expiration, :strikes_filter, :volume_oi_filter]
  }
end
