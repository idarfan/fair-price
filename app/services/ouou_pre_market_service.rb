# frozen_string_literal: true

# 歐歐每日盤前報告服務
# 蒐集市場數據 → 呼叫 Groq 生成 AI 評語 → 發送到 Telegram 群組
class OuouPreMarketService
  MAX_MSG_LEN = 4000 # Telegram 上限 4096，留緩衝

  def initialize
    @chat_id = ENV.fetch("OUOU_TELEGRAM_CHAT_ID") { raise "OUOU_TELEGRAM_CHAT_ID not set" }
  end

  # @return [Boolean] 是否成功發送
  def call
    report  = MomentumReportService.new(symbols: watchlist_symbols).call
    message = Ouou::PreMarketMessage.new(report).build
    send_to_telegram(message)
  rescue StandardError => e
    Rails.logger.error("[OuouPreMarket] Failed: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    false
  end

  private

  def send_to_telegram(html)
    telegram = TelegramService.new(chat_id: @chat_id)
    split_message(html).map { |chunk| telegram.send_message(chunk) }.all?
  end

  def split_message(text)
    return [ text ] if text.length <= MAX_MSG_LEN

    chunks  = []
    current = +""
    text.each_line do |line|
      if (current.length + line.length) > MAX_MSG_LEN
        chunks << current.strip unless current.blank?
        current = +""
      end
      current << line
    end
    chunks << current.strip unless current.blank?
    chunks
  end

  def watchlist_symbols
    WatchlistItem.ordered.map(&:symbol)
  rescue StandardError
    YAML.load_file(Rails.root.join("config/watchlist.yml")).fetch("symbols", [])
  end
end
