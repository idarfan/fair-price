# frozen_string_literal: true

# 解析 Telegram 傳入訊息，偵測 @OhmyOpenClawPriceBot 觸發，呼叫歐歐分析並回覆
class TelegramBotHandlerService
  BOT_USERNAME     = "OhmyOpenClawPriceBot"
  BOT_MENTION      = "@#{BOT_USERNAME}"
  ANALYSIS_RE      = /分析|看看|analysis|report|報告|新聞|news|公允|fair.?value/i
  TICKER_RE        = /\b([A-Z]{1,5})\b/
  EXCLUDED_TOKENS  = %w[A AN THE AND OR FOR OF IN ON AT TO IS IT AI ETF VIX SPX QQQ DOW S P ET USD TWD].freeze
  MAX_MSG_LEN      = 3800

  def initialize(update:)
    msg = update["message"] || update["edited_message"]
    return unless msg

    @message   = msg
    @text      = (msg["text"] || msg["caption"] || "").strip
    @chat_id   = msg.dig("chat", "id").to_s
    @chat_type = msg.dig("chat", "type") # "private" | "group" | "supergroup"
    @token     = ENV.fetch("TELEGRAM_BOT_TOKEN")
  end

  def call
    return unless @message
    return unless should_handle?

    ticker = extract_ticker
    return unless ticker

    Rails.logger.info("[TelegramBot] #{@chat_type} #{@chat_id} → #{ticker} 分析")
    send_typing_start
    analysis_html = collect_analysis(ticker)
    send_chunks(analysis_html)
  end

  private

  # ── Trigger detection ─────────────────────────────────────────────────────

  def should_handle?
    return true if @chat_type == "private"       # 私訊不需 @mention
    @text.include?(BOT_MENTION)                   # 群組需要 @mention
  end

  def extract_ticker
    clean = @text.gsub(/@\w+/, "").strip
    return nil unless clean.match?(ANALYSIS_RE)

    # 從文字中找大寫 1-5 字元 token（排除雜訊詞）
    tokens = clean.upcase.scan(TICKER_RE).flatten
    tokens.find { |t| t.length >= 2 && !EXCLUDED_TOKENS.include?(t) }
  end

  # ── Analysis (with typing indicator) ─────────────────────────────────────

  def collect_analysis(ticker)
    typing_active = true
    typing_thread = Thread.new do
      while typing_active
        send_typing_action
        sleep 4
      end
    end

    chunks = []
    OuouAnalysisService.new(symbol: ticker).call { |chunk| chunks << chunk }
    typing_active = false
    typing_thread.join(1)

    raw = chunks.join
    md_to_telegram_html(raw)
  rescue StandardError => e
    Rails.logger.error("[TelegramBot] Analysis error: #{e.message}")
    "😿 歐歐分析時發生錯誤：#{e.message}"
  end

  # ── Markdown → Telegram HTML ─────────────────────────────────────────────

  def md_to_telegram_html(text)
    lines   = text.split("\n")
    result  = []
    in_table = false
    table_buf = []

    lines.each do |line|
      if table_line?(line)
        in_table = true
        table_buf << line unless separator_line?(line)
      else
        if in_table
          result << table_to_pre(table_buf)
          table_buf = []
          in_table = false
        end
        result << convert_line(line)
      end
    end

    result << table_to_pre(table_buf) if table_buf.any?
    result.join("\n")
  end

  def table_line?(line)
    line.strip.start_with?("|") || line.strip.match?(/^\|[-| ]+\|$/)
  end

  def separator_line?(line)
    !line.match?(/[\p{L}\p{N}]/)
  end

  def table_to_pre(rows)
    return "" if rows.empty?

    cells = rows.map { |r| r.split("|").map(&:strip).reject(&:empty?) }
    header = cells.first
    body   = cells.drop(1)

    lines = body.map do |row|
      row.each_with_index.map { |val, i| "#{header[i]}：#{val}" }.join("  ")
    end
    "<pre>#{lines.join("\n")}</pre>"
  end

  def convert_line(line)
    line
      .gsub(/^#+\s+(.+)$/, '<b>\1</b>')
      .gsub(/\*\*(.+?)\*\*/, '<b>\1</b>')
      .gsub(/\*(.+?)\*/, '<i>\1</i>')
      .gsub(/^>\s*(.+)$/, '<i>\1</i>')
      .gsub(/^---+$/, "")
  end

  # ── Telegram API calls ────────────────────────────────────────────────────

  def send_typing_start
    send_typing_action
  end

  def send_typing_action
    HTTParty.post(
      "https://api.telegram.org/bot#{@token}/sendChatAction",
      headers: { "Content-Type" => "application/json" },
      body:    { chat_id: @chat_id, action: "typing" }.to_json,
      timeout: 5
    )
  rescue StandardError
    nil # typing indicator failure is non-critical
  end

  def send_chunks(html)
    telegram = TelegramService.new(chat_id: @chat_id)
    split_message(html).each { |chunk| telegram.send_message(chunk) }
  end

  def split_message(text)
    return [ text ] if text.length <= MAX_MSG_LEN

    chunks  = []
    current = +""

    text.each_line do |line|
      if current.length + line.length > MAX_MSG_LEN
        chunks << current.strip unless current.blank?
        current = +""
      end
      current << line
    end
    chunks << current.strip unless current.blank?
    chunks
  end
end
