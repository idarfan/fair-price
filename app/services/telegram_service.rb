# frozen_string_literal: true

# Sends HTML-formatted messages to a Telegram chat via Bot API.
# Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in environment.
class TelegramService
  BASE_URL = "https://api.telegram.org"

  def initialize(chat_id: nil)
    @token   = ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
    @chat_id = chat_id || ENV.fetch("TELEGRAM_CHAT_ID", nil)
    raise "TELEGRAM_BOT_TOKEN is not set" if @token.blank?
    raise "TELEGRAM_CHAT_ID is not set"   if @chat_id.blank?
  end

  def send_message(text)
    response = HTTParty.post(
      "#{BASE_URL}/bot#{@token}/sendMessage",
      headers: { "Content-Type" => "application/json" },
      body:    { chat_id: @chat_id, text: text, parse_mode: "HTML" }.to_json,
      timeout: 10
    )
    unless response.success?
      Rails.logger.error("[TelegramService] Failed: #{response.body}")
    end
    response.success?
  rescue HTTParty::Error, Net::ReadTimeout, SocketError => e
    Rails.logger.error("[TelegramService] Request failed: #{e.message}")
    false
  end
end
