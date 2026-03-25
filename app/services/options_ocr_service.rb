# frozen_string_literal: true

require "open3"
require "tempfile"

# 流程：EasyOCR（本地 Python）抽文字 → Groq（免費）解讀 → 結構化建議
class OptionsOcrService
  GROQ_API  = "https://api.groq.com/openai/v1/chat/completions"
  MODEL     = "llama-3.3-70b-versatile"
  PYTHON    = "python3"
  OCR_SCRIPT = Rails.root.join("scripts", "options_ocr.py").to_s

  def initialize(image_file)
    @image_file = image_file
  end

  def call
    # Step 1：把上傳的圖片存到暫存檔
    tmp = write_temp_image
    # Step 2：EasyOCR 抽文字
    raw_text = run_ocr(tmp.path)
    # Step 3：Groq 解讀 + 生成建議
    interpret(raw_text)
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  # ── Step 1 ─────────────────────────────────────────────────────────────────

  def write_temp_image
    ext = case @image_file.content_type.to_s
          when /jpeg|jpg/ then ".jpg"
          when /png/      then ".png"
          when /webp/     then ".webp"
          else ".png"
          end
    tmp = Tempfile.new(["options_ocr", ext], binmode: true)
    tmp.write(@image_file.read)
    tmp.flush
    tmp
  end

  # ── Step 2：EasyOCR subprocess ─────────────────────────────────────────────

  def run_ocr(image_path)
    stdout, stderr, status = Open3.capture3(PYTHON, OCR_SCRIPT, image_path)

    unless status.success?
      Rails.logger.error("[OptionsOcr] OCR script error: #{stderr}")
      raise "OCR 執行失敗，請確認 Python 環境"
    end

    parsed = JSON.parse(stdout)
    if parsed["error"]
      raise "OCR 錯誤：#{parsed['error']}"
    end

    text = parsed["text"].to_s.strip
    raise "圖片中未識別到任何文字，請上傳更清晰的截圖" if text.blank?

    Rails.logger.info("[OptionsOcr] Extracted #{parsed['count']} lines")
    text
  rescue JSON::ParserError
    raise "OCR 腳本輸出無法解析"
  end

  # ── Step 3：Groq 解讀 ──────────────────────────────────────────────────────

  def interpret(raw_text)
    api_key = ENV.fetch("GROQ_API_KEY") { raise "GROQ_API_KEY not set" }

    response = HTTParty.post(
      GROQ_API,
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json"
      },
      body: {
        model:      MODEL,
        max_tokens: 1024,
        stream:     false,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user",   content: "以下是從截圖 OCR 提取的文字，請分析：\n\n#{raw_text}" }
        ]
      }.to_json,
      timeout: 30
    )

    raise "Groq API 錯誤 #{response.code}" unless response.success?

    content = response.parsed_response.dig("choices", 0, "message", "content").to_s.strip
    parse_groq_response(content)
  end

  def system_prompt
    <<~PROMPT
      你是一位專業的美股期權交易分析師。
      使用者提供了從截圖 OCR 出來的文字（可能含有圖表、選擇權鏈、券商介面等資訊）。
      請分析這些文字並回傳一個 JSON 物件，不要加任何 markdown 或說明。

      JSON 格式：
      {
        "symbol":         "股票代號（大寫），如找不到填 ''",
        "price":          現股價 (number) 或 null,
        "iv_rank":        IV Rank 0-100 (number) 或 null,
        "outlook":        "bullish" | "bearish" | "neutral" | "volatile",
        "outlook_reason": "一句話說明判斷依據（繁體中文）",
        "legs": [
          {
            "type":     "long_call" | "short_call" | "long_put" | "short_put",
            "strike":   數字,
            "premium":  每股 Premium 數字,
            "quantity": 口數（預設 1）,
            "dte":      到期天數 或 null,
            "iv":       隱含波動率小數 如 0.45 或 null
          }
        ],
        "strategy_hint":  "如果看得出來是什麼策略，填策略名稱，否則填 ''",
        "recommendation": "2-4 句話的期權操作建議（繁體中文）",
        "confidence":     "high" | "medium" | "low",
        "notes":          "其他有用的資訊（繁體中文）"
      }

      規則：
      - 若無法識別某欄位，用 null（數字）或 ""（文字）
      - legs 只在截圖中明確看到期權合約資料時才填，否則給空陣列 []
      - premium 是每股金額（不乘 100）
      - 只回傳 JSON，第一個字元是 {，最後一個字元是 }
    PROMPT
  end

  def parse_groq_response(content)
    json_str = content.match(/\{.*\}/m)&.to_s
    raise "Groq 回應中找不到 JSON" if json_str.blank?

    raw = JSON.parse(json_str)

    symbol = raw["symbol"].to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10)

    valid_types = %w[long_call short_call long_put short_put]
    legs = Array(raw["legs"]).filter_map do |l|
      type = l["type"].to_s
      next unless valid_types.include?(type)
      strike  = l["strike"].to_f
      premium = l["premium"].to_f
      next unless strike > 0 && premium > 0
      {
        type:     type,
        strike:   strike.round(2),
        premium:  premium.round(2),
        quantity: [l["quantity"].to_i, 1].max,
        dte:      l["dte"]&.to_i,
        iv:       l["iv"]&.to_f&.round(4)
      }
    end

    {
      symbol:         symbol,
      price:          raw["price"]&.to_f,
      iv_rank:        raw["iv_rank"]&.to_f,
      outlook:        %w[bullish bearish neutral volatile].include?(raw["outlook"]) ? raw["outlook"] : "neutral",
      outlook_reason: raw["outlook_reason"].to_s,
      legs:           legs,
      strategy_hint:  raw["strategy_hint"].to_s,
      recommendation: raw["recommendation"].to_s,
      confidence:     %w[high medium low].include?(raw["confidence"]) ? raw["confidence"] : "low",
      notes:          raw["notes"].to_s
    }
  rescue JSON::ParserError => e
    Rails.logger.error("[OptionsOcr] Groq JSON parse failed: #{e.message}")
    raise "AI 解讀失敗，請重試"
  end
end
