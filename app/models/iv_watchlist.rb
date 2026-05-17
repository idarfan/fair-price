# frozen_string_literal: true

class IvWatchlist < ApplicationRecord
  GROUP_TAGS = %w[general index leveraged macro].freeze

  validates :symbol,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: {
              with: /\A[A-Za-z\-\.]{1,10}\z/,
              message: "只允許英文字母、- 和 ."
            }
  validates :group_tag, inclusion: { in: GROUP_TAGS }

  before_save { self.symbol = symbol.upcase.strip }

  scope :active,   -> { where(active: true) }
  scope :by_group, -> { order(:group_tag, :symbol) }
end
