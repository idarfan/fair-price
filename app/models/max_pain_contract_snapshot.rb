# frozen_string_literal: true

class MaxPainContractSnapshot < ApplicationRecord
  validates :symbol, :snapshot_date, :fetched_at, presence: true
  validates :symbol, uniqueness: { scope: :snapshot_date }
end
