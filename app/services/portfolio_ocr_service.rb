# frozen_string_literal: true

class PortfolioOcrService
  ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
  MODEL         = "claude-sonnet-4-6"

  def initialize(image_file)
    @image_file = image_file
  end

  # Returns Array<{ symbol:, shares:, unit_cost: }>
  def call
    image_data = Base64.strict_encode64(@image_file.read)
    media_type = normalize_media_type(@image_file.content_type)

    response = HTTParty.post(
      ANTHROPIC_API,
      headers: {
        "x-api-key"         => ENV.fetch("ANTHROPIC_API_KEY"),
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: {
        model:      MODEL,
        max_tokens: 2048,
        messages:   [
          {
            role:    "user",
            content: [
              {
                type:   "image",
                source: { type: "base64", media_type: media_type, data: image_data }
              },
              { type: "text", text: ocr_prompt }
            ]
          }
        ]
      }.to_json,
      timeout: 60
    )

    parse_response(response)
  rescue StandardError => e
    Rails.logger.error("[PortfolioOcr] #{e.class}: #{e.message}")
    raise
  end

  private

  def ocr_prompt
    <<~PROMPT
      This image contains a stock portfolio table. Extract every holding row and return ONLY a JSON array.

      For each row extract these three fields:
      - "symbol"    : stock ticker symbol (uppercase string, e.g. "AAPL")
      - "shares"    : number of shares held (decimal, column header may say 股數)
      - "unit_cost" : cost per share (decimal, column header may say 單位成本)

      Rules:
      - Skip the header row
      - Skip any row where shares or unit_cost is 0 or blank
      - Return ONLY the raw JSON array, no markdown fences, no explanation

      Example output:
      [{"symbol":"AAPL","shares":10.5,"unit_cost":150.25},{"symbol":"TSLA","shares":5,"unit_cost":200.00}]
    PROMPT
  end

  def parse_response(response)
    raise "API error: #{response.code}" unless response.success?

    text = response.parsed_response.dig("content", 0, "text").to_s.strip
    json_str = text.match(/\[.*\]/m)&.to_s
    raise "No JSON array found in response" if json_str.blank?

    JSON.parse(json_str).filter_map do |row|
      symbol    = row["symbol"].to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").strip
      shares    = row["shares"].to_f
      unit_cost = row["unit_cost"].to_f

      next if symbol.blank? || shares <= 0 || unit_cost <= 0

      { symbol: symbol, shares: shares, unit_cost: unit_cost }
    end
  rescue JSON::ParserError => e
    Rails.logger.error("[PortfolioOcr] JSON parse failed: #{e.message}\nRaw: #{text}")
    raise "OCR 結果無法解析，請再試一次"
  end

  def normalize_media_type(content_type)
    case content_type.to_s
    when /jpeg|jpg/ then "image/jpeg"
    when /png/      then "image/png"
    when /gif/      then "image/gif"
    when /webp/     then "image/webp"
    else "image/png"
    end
  end
end
