# frozen_string_literal: true

module Ouou
  # Builds the pre-market HTML message from a MomentumReportService result.
  # Produces a header section (pure Ruby) and an AI analysis section (Groq).
  class PreMarketMessage
    GROQ_API   = "https://api.groq.com/openai/v1/chat/completions"
    MODEL      = "llama-3.3-70b-versatile"
    MAX_TOKENS = 1200

    def initialize(report)
      @report  = report
      @api_key = ENV.fetch("GROQ_API_KEY") { raise "GROQ_API_KEY not set" }
    end

    # @return [String] Telegram-compatible HTML
    def build
      build_header + groq_section
    end

    private

    # ── Header (pure Ruby) ───────────────────────────────────────

    def build_header
      vix    = @report[:vix]
      stance = derive_stance(vix)

      lines = []
      lines << "<b>🐱 歐歐盤前日報 #{Date.current.strftime('%Y-%m-%d')}</b>"
      lines << ""
      lines << "<b>🌡 市場溫度</b>"
      lines << "- VIX：#{vix&.round(2) || '—'}（#{stance_label(stance)}）"
      lines << "- ES 期貨（標普）：#{format_change(@report[:es_change])}"
      lines << "- NQ 期貨（那斯達克）：#{format_change(@report[:nq_change])}"
      lines << ""

      stocks = @report[:stocks]
      if stocks.any?
        lines << "<b>📋 觀察名單</b>"
        stocks.each do |s|
          pct  = (s[:change_pct] * 100).round(2)
          sign = pct >= 0 ? "+" : ""
          lines << "- #{s[:symbol]}：$#{s[:price].round(2)}（#{sign}#{pct}%）"
        end
        lines << ""
      end

      earnings = @report[:earnings]
      if earnings.any?
        lines << "<b>📅 近期財報</b>"
        earnings.each { |e| lines << "- #{e[:symbol]}（#{e[:date]}）" }
        lines << ""
      end

      lines.join("\n")
    end

    # ── Groq AI section ──────────────────────────────────────────

    def groq_section
      text = call_groq(build_prompt)
      return "" if text.blank?

      "\n<b>🐱 歐歐分析</b>\n#{md_to_html(text)}"
    end

    def build_prompt
      vix    = @report[:vix]
      stance = derive_stance(vix)
      stocks = @report[:stocks].map { |s|
        pct = (s[:change_pct] * 100).round(2)
        "#{s[:symbol]}: $#{s[:price].round(2)}（#{pct >= 0 ? '+' : ''}#{pct}%）"
      }.join(", ")

      <<~PROMPT
        今天是 #{Date.current.strftime("%Y-%m-%d")}，美股盤前時段。

        市場數據：
        - VIX：#{vix&.round(2) || '—'}（#{stance_label(stance)}）
        - ES 期貨：#{format_change(@report[:es_change])}
        - NQ 期貨：#{format_change(@report[:nq_change])}
        - 觀察名單：#{stocks.presence || '（無資料）'}

        請用歐歐的風格給出今日盤前簡短分析（3 段以內）：
        整體市場氣氛、盤前值得關注的訊號、以及操作心法提醒。
      PROMPT
    end

    def call_groq(prompt)
      uri     = URI(GROQ_API)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["content-type"]  = "application/json"
      request.body = {
        model:      MODEL,
        max_tokens: MAX_TOKENS,
        messages:   [
          { role: "system", content: system_prompt },
          { role: "user",   content: prompt }
        ],
        stream: false
      }.to_json

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        response = http.request(request)
        parsed   = JSON.parse(response.body)
        parsed.dig("choices", 0, "message", "content").to_s
      end
    rescue Net::ReadTimeout, SocketError, JSON::ParserError => e
      Rails.logger.error("[OuouPreMarket] Groq API error: #{e.message}")
      ""
    end

    def system_prompt
      <<~'SYSTEM'
        你是歐歐 🐱，一隻招財貓投資分析師。說話帶點貓性俏皮，但分析數據紮實。全程繁體中文。

        格式規定（Telegram 相容）：
        - 禁止使用 Markdown 表格（不可用 | 符號）
        - 使用條列式（- 開頭）或 emoji 開頭
        - 章節標題可用 **粗體** 格式，但不用 ## 標題符號
        - 全文 3 段以內，約 400–600 字
        - 最後一句必須帶貓咪 emoji（🐾 或 🐱）
      SYSTEM
    end

    # ── Helpers ──────────────────────────────────────────────────

    def derive_stance(vix)
      return :cash if vix.nil?

      if    vix < MomentumThresholds::VIX_AGGRESSIVE_MAX    then :aggressive
      elsif vix <= MomentumThresholds::VIX_CONSERVATIVE_MAX then :conservative
      else                                                        :cash
      end
    end

    def stance_label(stance)
      case stance
      when :aggressive   then "🟢 激進買入"
      when :conservative then "🟡 保守買入"
      else                    "🔴 持幣觀望"
      end
    end

    def format_change(pct)
      return "—" if pct.nil?

      pct_r = pct.round(2)
      "#{pct_r >= 0 ? '+' : ''}#{pct_r}%"
    end

    def md_to_html(text)
      text
        .gsub(/\*\*(.+?)\*\*/, '<b>\1</b>')
        .gsub(/\*(.+?)\*/, '<i>\1</i>')
        .gsub(/^#+\s+(.+)$/, '<b>\1</b>')
        .gsub(/^>\s+(.+)$/, '<i>\1</i>')
        .gsub(/^---+$/, "")
    end
  end
end
