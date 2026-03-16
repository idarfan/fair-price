# frozen_string_literal: true

class PriceAlert < ApplicationRecord
  VALID_CONDITIONS = %w[above below].freeze

  validates :symbol,       presence: true
  validates :target_price, presence: true, numericality: { greater_than: 0 }
  validates :condition,    presence: true, inclusion: { in: VALID_CONDITIONS }

  scope :active, -> { where(active: true) }

  before_save   :upcase_symbol
  before_create :set_position

  def triggered?
    triggered_at.present?
  end

  private

  def upcase_symbol
    self.symbol = symbol.upcase
  end

  def set_position
    self.position = (self.class.maximum(:position) || -1) + 1
  end
end
