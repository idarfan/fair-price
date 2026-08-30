# frozen_string_literal: true

class IvWatchlist < ApplicationRecord
  belongs_to :user

  GROUP_TAGS = %w[general index leveraged macro].freeze

  # 移到 before_validation：原本在 before_save 時，唯一性與 format 兩個驗證
  # 都跑在未正規化的值上（" aapl " 會因為空白被 format 擋掉）。
  before_validation { self.symbol = symbol&.upcase&.strip }

  validates :symbol,
            presence: true,
            uniqueness: { scope: :user_id },
            format: {
              with: /\A[A-Za-z\-\.]{1,10}\z/,
              message: "只允許英文字母、- 和 ."
            }
  validates :group_tag, inclusion: { in: GROUP_TAGS }

  scope :active,   -> { where(active: true) }
  scope :by_group, -> { order(:group_tag, :symbol) }
end
