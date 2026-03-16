# frozen_string_literal: true

class WatchlistItem < ApplicationRecord
  validates :symbol, presence: true,
                     uniqueness: { case_sensitive: false },
                     format: { with: /\A[A-Za-z0-9.\-]{1,10}\z/, message: "格式不正確" }

  before_validation { self.symbol = symbol&.upcase&.strip }

  scope :ordered, -> { order(:position, :created_at) }

  def self.next_position
    maximum(:position).to_i + 1
  end
end
