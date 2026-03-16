# frozen_string_literal: true

class OwnershipHolder < ApplicationRecord
  belongs_to :ownership_snapshot

  validates :name, presence: true
  validates :name, uniqueness: { scope: :ownership_snapshot_id }
end
