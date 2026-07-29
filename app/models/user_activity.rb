# frozen_string_literal: true

class UserActivity < ApplicationRecord
  belongs_to :user

  enum :kind, { page_view: 0, command: 1 }

  validates :started_at, presence: true

  scope :recent, -> { where(created_at: 7.days.ago..) }
end
