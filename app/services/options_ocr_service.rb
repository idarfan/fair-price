# frozen_string_literal: true

require "base64"

# 流程：圖片 base64 → Groq Vision（llama-4-scout）直接解讀 → 結構化建議
# 移除 EasyOCR 依賴（太慢、需下載大模型、CPU 無法在合理時間內完成）
class OptionsOcrService
  GROQ_API     = "https://api.groq.com/openai/v1/chat/completions"
  VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

  def initialize(image_file, system_data: {})
    @image_file  = image_file
    @system_data = system_data
  end

  def call
    b64  = encode_image
    mime = @image_file.content_type.to_s.presence || "image/png"

    # 若前端沒傳 IV 數據，後端自行補齊（兩階段：先識別 symbol → 再查 HV Rank）
    enrich_system_data_if_needed!(b64, mime)

    analyze_with_vision(b64, mime)
  end

  private

  # 若前端沒有傳入 IV 數據，嘗試從截圖中辨識 symbol 後自動查詢
  def enrich_system_data_if_needed!(b64, mime)
    return if @system_data["iv_rank"].present?

    # 先嘗試用前端傳來的 symbol
    sym = @system_data["symbol"].to_s.strip
    if sym.blank?
      # 快速呼叫 Groq 只辨識 symbol
      sym = quick_identify_symbol(b64, mime)
    end
    return if sym.blank?

    Rails.logger.info("[OptionsOcr] enriching system_data for symbol=#{sym}")
    iv_data = IvRankService.new(sym).call

    @system_data = @system_data.merge(
      "symbol"     => sym,
      "iv_rank"    => iv_data[:iv_rank],
      "current_hv" => iv_data[:current_hv],
      "hv_high"    => iv_data[:hv_high],
      "hv_low"     => iv_data[:hv_low],
      "iv_comment" => iv_data[:iv_comment],
      "peers"      => iv_data[:peers]&.map { |p| { "symbol" => p[:symbol], "iv" => p[:iv], "iv_rank" => p[:iv_rank] } } || []
    )

    # 也查現價
    if @system_data["price"].to_f <= 0
      quote = FinnhubService.new.quote(sym)
      @system_data["price"] = quote&.dig("c").to_f if quote
    end
  rescue StandardError => e
    Rails.logger.warn("[OptionsOcr] enrich failed: #{e.message}")
  end

  def quick_identify_symbol(b64, mime)
    api_key = ENV.fetch("GROQ_API_KEY") { return nil }

    response = HTTParty.post(
      GROQ_API,
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json"
      },
      body: {
        model:      VISION_MODEL,
        max_tokens: 50,
        stream:     false,
        messages: [
          {
            role:    "user",
            content: [
              { type: "text", text: "這張券商截圖中的股票代號是什麼？只回覆大寫代號，例如 AAPL。如果找不到，回覆 UNKNOWN。" },
              { type: "image_url", image_url: { url: "data:#{mime};base64,#{b64}" } }
            ]
          }
        ]
      }.to_json,
      timeout: 15
    )

    return nil unless response.success?
    raw = response.parsed_response.dig("choices", 0, "message", "content").to_s.strip.upcase
    sym = raw.gsub(/[^A-Z0-9.\-]/, "").first(10)
    sym == "UNKNOWN" || sym.blank? ? nil : sym
  rescue StandardError => e
    Rails.logger.warn("[OptionsOcr] quick_identify failed: #{e.message}")
    nil
  end

  def encode_image
    data = @image_file.read
    raise "圖片太大（上限 3MB）" if data.bytesize > 3 * 1024 * 1024
    Base64.strict_encode64(data)
  end

  def analyze_with_vision(b64, mime)
    api_key = ENV.fetch("GROQ_API_KEY") { raise "GROQ_API_KEY not set" }

    response = HTTParty.post(
      GROQ_API,
      headers: {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json"
      },
      body: {
        model:      VISION_MODEL,
        max_tokens: 8000,
        stream:     false,
        messages: [
          {
            role:    "user",
            content: [
              { type: "text", text: vision_prompt },
              {
                type:      "image_url",
                image_url: { url: "data:#{mime};base64,#{b64}" }
              }
            ]
          }
        ]
      }.to_json,
      timeout: 60
    )

    raise "Groq Vision API 錯誤 #{response.code}" unless response.success?

    content = response.parsed_response.dig("choices", 0, "message", "content").to_s.strip
    parse_groq_response(content)
  end

  def vision_prompt
    base = <<~PROMPT
      你是一位資深美股期權交易員，擅長 Covered Call、Cash Secured Put、Iron Condor、Credit Spread 等策略。
      使用者上傳了券商截圖（期權鏈、股價圖、P&L 圖等）。
      請深度分析截圖內容並回傳 JSON，不加任何 markdown 包裝或說明文字。
    PROMPT

    # 注入系統已計算好的數據
    Rails.logger.info("[OptionsOcr] system_data=#{@system_data.inspect}")
    if @system_data.present?
      base += "\n以下是系統已從市場數據計算好的即時資訊，請務必在 recommendation 中引用：\n"
      base += "- 股票代號：#{@system_data['symbol']}\n" if @system_data["symbol"].present?
      base += "- 現價：$#{@system_data['price']}\n" if @system_data["price"].present?
      base += "- HV Rank（歷史波動率排名）：#{@system_data['iv_rank']}\n" if @system_data["iv_rank"].present?
      base += "- 目前 30 日 HV：#{@system_data['current_hv']}%\n" if @system_data["current_hv"].present?
      base += "- 一年 HV 高點：#{@system_data['hv_high']}%，低點：#{@system_data['hv_low']}%\n" if @system_data["hv_high"].present?
      base += "- HV 評語：#{@system_data['iv_comment']}\n" if @system_data["iv_comment"].present?

      peers = @system_data["peers"]
      if peers.is_a?(Array) && peers.any?
        base += "- 同類股 HV Rank 比較：#{peers.map { |p| "#{p['symbol']} IV=#{p['iv']}% Rank=#{p['iv_rank']}" }.join('、')}\n"
      end
      base += "\n"
    end

    base += <<~PROMPT

      JSON 格式：
      {
        "symbol":         "股票代號（大寫），找不到填 ''",
        "price":          現股價 number 或 null,
        "iv_rank":        IV Rank 0-100 number 或 null,
        "outlook":        "bullish" | "bearish" | "neutral" | "volatile",
        "outlook_reason": "用繁體中文說明看多/看空/中性判斷依據，引用截圖中的具體數字與上方系統數據",
        "legs": [
          {
            "type":     "long_call" | "short_call" | "long_put" | "short_put",
            "strike":   數字,
            "premium":  每股 premium（bid/ask 中間價），不乘 100,
            "quantity": 口數預設 1,
            "dte":      到期天數 或 null,
            "iv":       隱含波動率小數如 0.65 或 null
          }
        ],
        "strategy_hint":  "識別到的策略名稱（英文），找不到填 ''",
        "recommendation": "深度操作建議（繁體中文，400-600字）：\\n1. 結合系統提供的 HV Rank 和截圖中的 IV 數據，評估目前波動率水平\\n2. 說明截圖中最值得關注的 strike/premium 組合\\n3. 計算年化報酬率（premium / 鎖定資金 × 365 / DTE）\\n4. 計算損益兩平價（breakeven = strike - premium 或 strike + premium）\\n5. 分析風險：HV/IV 高低、被指派機率、跳空風險\\n6. 保守/積極兩種操作方案各一句\\n7. 與同類股的波動率比較和關聯風險提醒",
        "confidence":     "high" | "medium" | "low",
        "notes":          "補充說明（繁體中文）"
      }

      規則：
      - recommendation 必須引用截圖中的真實數字及系統提供的 HV Rank、HV 數據，不可泛泛而談
      - 若系統提供了 HV Rank，必須在建議中明確說明目前 HV 水平處於歷史什麼位置，對策略選擇的影響
      - legs 只在截圖有明確合約資料時填，否則給 []
      - premium 是每股金額（contract = premium × 100）
      - 只回傳 JSON，第一個字元 { 最後一個字元 }
    PROMPT

    base
  end

  def parse_groq_response(content)
    json_str = content.match(/\{.*\}/m)&.to_s
    raise "Groq Vision 回應中找不到 JSON" if json_str.blank?

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
