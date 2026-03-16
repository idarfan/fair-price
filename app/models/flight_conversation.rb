# frozen_string_literal: true

class FlightConversation < ApplicationRecord
  has_many :flight_messages, -> { order(:created_at) }, dependent: :destroy, inverse_of: :flight_conversation

  validates :token, presence: true, uniqueness: true

  # 依 token 找到對話，不存在就建立新的
  def self.find_or_create_for_token(token)
    find_by(token: token) || create!(token: SecureRandom.urlsafe_base64(24))
  end

  # 回傳所有訊息，兩兩配對成 [{question:, answer:, index:}, ...]
  def message_pairs
    msgs = flight_messages.to_a
    msgs.each_slice(2).with_index.map do |(user_msg, asst_msg), idx|
      { index: idx, question: user_msg.content, answer: asst_msg&.content }
    end
  end

  # 回傳 API 需要的 history 格式
  def history_for_api
    flight_messages.map { |m| { role: m.role, content: m.content } }
  end
end
