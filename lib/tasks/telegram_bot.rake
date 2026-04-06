# frozen_string_literal: true

namespace :telegram do
  desc "啟動歐歐 Telegram Bot（長輪詢，阻塞式執行）"
  task bot: :environment do
    TelegramBotPollingService.new.run
  end
end
