# frozen_string_literal: true

class WatchlistItem < ApplicationRecord
  belongs_to :user

  validates :symbol, presence: true,
                     uniqueness: { scope: :user_id, case_sensitive: false },
                     format: { with: /\A[A-Za-z0-9.\-]{1,10}\z/, message: "格式不正確" }

  before_validation { self.symbol = symbol&.upcase&.strip }

  scope :ordered, -> { order(:position, :created_at) }

  # 呼叫端必須從使用者出發（current_user.watchlist_items.next_position），
  # 否則新使用者的第一筆會拿到別人的序號。
  def self.next_position
    maximum(:position).to_i + 1
  end
end
