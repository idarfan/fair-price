# frozen_string_literal: true

class UserActivity < ApplicationRecord
  belongs_to :user

  enum :kind, { page_view: 0, command: 1 }

  # kind 與 started_at 在 DB 都是 NOT NULL；沒有 model 驗證時 nil 會拋原始
  # PG 例外而不是驗證錯誤（database_consistency NullConstraintChecker）。
  validates :kind, :started_at, presence: true

  scope :recent, -> { where(created_at: 7.days.ago..) }
end
