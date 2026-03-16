# frozen_string_literal: true

class OuouAnalysisService
  ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
  MODEL         = "claude-opus-4-6"
  MAX_TOKENS    = 4096
  CACHE_TTL     = 3.hours
  CACHE_PREFIX  = "ouou_analysis"

  def initialize(symbol:)
    @symbol  = symbol.upcase
    @finnhub = FinnhubService.new
    @api_key = ENV.fetch("ANTHROPIC_API_KEY") { raise "ANTHROPIC_API_KEY not set" }
  end

  # Yields text chunks as they stream from Claude.
  # On cache hit (and force: false), yields the full cached text in one shot.
  def call(&block)
    if (cached = Rails.cache.read(cache_key))
      block.call(cached)
      return
    end

    market_data = collect_market_data
    prompt      = build_prompt(market_data)
    accumulated = +""

    stream_request(prompt) do |chunk|
      accumulated << chunk
      block.call(chunk)
    end

    if accumulated.present?
      footer = analysis_date_footer
      block.call(footer)
      Rails.cache.write(cache_key, accumulated + footer, expires_in: CACHE_TTL)
    end
  end

  private

  def stream_request(prompt, &block)
    uri     = URI(ANTHROPIC_API)
    request = build_http_request(uri, prompt)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
      http.request(request) do |response|
        response.read_body do |chunk|
          parse_sse_chunk(chunk, &block)
        end
      end
    end
  end

  def build_http_request(uri, prompt)
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"]         = @api_key
    req["anthropic-version"] = "2023-06-01"
    req["content-type"]      = "application/json"
    req.body = {
      model:      MODEL,
      max_tokens: MAX_TOKENS,
      system:     system_prompt,
      messages:   [ { role: "user", content: prompt } ],
      stream:     true
    }.to_json
    req
  end

  def parse_sse_chunk(chunk, &block)
    chunk.each_line do |line|
      next unless line.start_with?("data: ")

      data = line[6..].strip
      next if data == "[DONE]" || data.empty?

      parsed = JSON.parse(data)
      next unless parsed["type"] == "content_block_delta"
      next unless parsed.dig("delta", "type") == "text_delta"

      text = parsed.dig("delta", "text")
      block.call(text) if text&.present?
    rescue JSON::ParserError
      next
    end
  end

  def collect_market_data
    quote = @finnhub.quote(@symbol)
    yahoo = YahooFinanceService.new.chart(@symbol, range: "1y")
    news  = @finnhub.company_news(@symbol,
                                  from_date: (Date.current - 7).to_s,
                                  to_date:   Date.current.to_s)
    {
      quote: quote,
      yahoo: yahoo,
      news:  news.first(5),
      vix:   VixService.new.fetch
    }
  end

  def build_prompt(data) # rubocop:disable Metrics/MethodLength
    quote   = data[:quote]
    yahoo   = data[:yahoo]
    news    = data[:news]
    vix     = data[:vix]
    closes  = yahoo[:closes]
    volumes = yahoo[:volumes]
    price   = quote&.dig("c").to_f

    news_text = news.map.with_index(1) do |item, i|
      "#{i}. #{item['headline']} (#{item['source']})"
    end.join("\n")

    <<~PROMPT
      請分析 #{@symbol} 的投資機會。

      ## 即時市場數據
      - 現價：#{price} USD
      - 今日漲跌：#{quote&.dig('dp')&.round(2)}%（#{quote&.dig('d')&.round(2)} USD）
      - 開盤 #{quote&.dig('o')} ｜ 最高 #{quote&.dig('h')} ｜ 最低 #{quote&.dig('l')}
      - 52週高：#{yahoo[:high_52w] || '—'} ｜ 52週低：#{yahoo[:low_52w] || '—'}
      - 52週位置：#{position_in_52w(price, yahoo[:low_52w], yahoo[:high_52w])}
      - VIX：#{vix || '—'}

      ## 動量數據（此表格已由系統產生，請在技術面分析的動量觀察小節原文輸出，不得更改任何符號或格式）
      #{build_momentum_table(closes, volumes)}

      ## 近期新聞（過去7天）
      #{news_text.presence || '（無新聞資料）'}

      請依據歐歐的分析框架，針對 #{@symbol} 給出完整的個股分析報告。
    PROMPT
  end

  def build_momentum_table(closes, volumes)
    rows = [
      [ "5日動量",  compute_momentum(closes, 5)  ],
      [ "20日動量", compute_momentum(closes, 20) ],
      [ "成交量",   volume_vs_avg(volumes)        ]
    ]
    lines = [ "| 指標 | 數值 |", "|---|---|" ]
    rows.each { |name, val| lines << "| #{name} | #{val} |" }
    lines.join("\n")
  end

  def compute_momentum(closes, days)
    return "N/A" if closes.size <= days

    pct = ((closes.last - closes[-(days + 1)]) / closes[-(days + 1)].to_f * 100).round(2)
    "#{pct >= 0 ? '+' : ''}#{pct}%"
  end

  def position_in_52w(price, low, high)
    return "N/A" unless price.positive? && low && high && (high - low).nonzero?

    pct      = ((price - low) / (high - low) * 100).round(1)
    from_low = ((price - low) / low * 100).round(1)
    from_high = ((high - price) / high * 100).round(1)
    "區間 #{pct}%（距52週低 +#{from_low}%，距52週高 -#{from_high}%）"
  end

  def volume_vs_avg(volumes)
    return "N/A" if volumes.size < 20

    avg   = (volumes.last(20).sum / 20.0).round(0).to_i
    today = volumes.last.to_i
    ratio = avg.positive? ? (today.to_f / avg * 100).round(0) : nil
    "#{fmt_vol(today)} vs 20日均量 #{fmt_vol(avg)}#{ratio ? "（#{ratio}%）" : ''}"
  end

  def analysis_date_footer
    ts = Time.current.in_time_zone("Eastern Time (US & Canada)").strftime("%Y-%m-%d %H:%M ET")
    "\n\n---\n\n📌 本分析為歐歐AI基於Finnhub公開數據的觀點，不構成投資建議，請自行評估風險。🐾\n\n*分析時間：#{ts}*"
  end

  def cache_key
    "#{CACHE_PREFIX}:#{@symbol}"
  end

  def fmt_vol(n)
    return "—" unless n&.positive?

    if n >= 1_000_000
      "#{(n / 1_000_000.0).round(1)}M"
    elsif n >= 1_000
      "#{(n / 1_000.0).round(0).to_i}K"
    else
      n.to_s
    end
  end

  def system_prompt # rubocop:disable Metrics/MethodLength
    <<~SYSTEM
      你是歐歐 🐱，一隻招財貓投資分析師。說話帶點貓性俏皮，但分析數據絕對紮實。全程使用繁體中文。

      ## 分析框架

      ### 1. 🐱 市場立場（必須基於 VIX）
      - VIX < 16：🟢 激進買入
      - VIX 16–22：🟡 保守買入
      - VIX > 22：🔴 持幣觀望

      輸出：`歐歐立場：[立場] ｜ VIX:[值] ｜ 邏輯：[2句]`

      ### 2. 📊 技術面分析
      - 5日動量評估
      - 52週位置（接近高點 / 低點 / 中間）
      - 支撐與阻力位估算

      ### 3. 📰 催化因素
      - 基於近期新聞的主要催化劑

      ### 4. 🎯 操作建議
      - 入場觸發條件
      - 止損位
      - 目標價（短線 / 中線）
      - 成功概率估計（%）
      - 風報比

      ### 5. ⚠️ 風險提示
      - 主要下行風險（3點）
      - 單筆最大倉位建議

      輸出請使用 Markdown 格式，標題清晰，條列整齊。結尾不需附加任何免責聲明。
    SYSTEM
  end
end
