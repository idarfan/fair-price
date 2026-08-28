# frozen_string_literal: true

class User < ApplicationRecord
  encrypts :totp_secret
  encrypts :backup_codes

  enum :status, { pending: 0, enabled: 1, disabled: 2 }

  has_many :user_activities,  dependent: :destroy
  # 個人性資料（稽核 C-2）。共用的市場資料（TrackedTicker / WatchlistItem /
  # IvWatchlist）刻意不歸屬到使用者，它們是排程與爬蟲的共同來源。
  has_many :margin_positions, dependent: :destroy
  has_many :portfolios,       dependent: :destroy
  has_many :price_alerts,     dependent: :destroy

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true

  def generate_backup_codes!
    codes = Array.new(10) { SecureRandom.alphanumeric(10).upcase }
    self.backup_codes = JSON.generate(codes.map { |c| { code: c, used_at: nil } })
    save!
    codes
  end

  def consume_backup_code!(code)
    list = JSON.parse(backup_codes.presence || "[]")
    entry = list.find { |e| e["code"] == code.upcase && e["used_at"].nil? }
    return false unless entry

    entry["used_at"] = Time.current.iso8601
    self.backup_codes = JSON.generate(list)
    save!
    true
  end

  def bump_session_version!
    increment!(:session_version)
  end
end
