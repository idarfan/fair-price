# frozen_string_literal: true

# Telegram Long Polling 服務
# 持續從 Telegram 取得新訊息，交給 TelegramBotHandlerService 處理
class TelegramBotPollingService
  POLL_TIMEOUT = 30 # 秒，Telegram 長輪詢等待時間
  RETRY_DELAY  = 5  # 秒，錯誤後重試間隔

  def initialize
    @token  = ENV.fetch("TELEGRAM_BOT_TOKEN") { raise "TELEGRAM_BOT_TOKEN not set" }
    @offset = 0
  end

  def run
    Rails.logger.info("[TelegramBot] 🐱 歐歐 long polling 已啟動（@OhmyOpenClawPriceBot）")
    loop { poll_once }
  end

  private

  def poll_once
    updates = fetch_updates
    updates.each { |u| handle_update(u) }
  rescue Net::ReadTimeout
    # 正常：長輪詢 timeout，繼續下一輪
    retry
  rescue StandardError => e
    Rails.logger.error("[TelegramBot] 錯誤：#{e.class} #{e.message}")
    sleep RETRY_DELAY
    retry
  end

  def fetch_updates
    response = HTTParty.get(
      "https://api.telegram.org/bot#{@token}/getUpdates",
      query:   { offset: @offset, timeout: POLL_TIMEOUT },
      timeout: POLL_TIMEOUT + 5
    )
    parsed  = response.parsed_response
    updates = parsed["result"] || []
    @offset = updates.last["update_id"] + 1 if updates.any?
    updates
  end

  def handle_update(update)
    TelegramBotHandlerService.new(update: update).call
  rescue StandardError => e
    Rails.logger.error("[TelegramBot] handle_update 失敗：#{e.message}")
  end
end
