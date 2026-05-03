# frozen_string_literal: true

class IvQuery < ApplicationRecord
  validates :ticker, :option_type, presence: true
  validates :option_type, inclusion: { in: %w[call put] }
end
