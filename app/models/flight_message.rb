# frozen_string_literal: true

class FlightMessage < ApplicationRecord
  belongs_to :flight_conversation

  ROLES = %w[user assistant].freeze

  validates :role,    presence: true, inclusion: { in: ROLES }
  validates :content, presence: true
end
