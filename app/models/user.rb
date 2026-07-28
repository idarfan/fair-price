# frozen_string_literal: true

class User < ApplicationRecord
  encrypts :totp_secret
  encrypts :backup_codes

  enum :status, { pending: 0, enabled: 1, disabled: 2 }

  has_many :user_activities, dependent: :destroy

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true
end
