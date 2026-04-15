# frozen_string_literal: true

class OuouAnalysisService
  include Charts::TechnicalIndicators

  GROQ_API   = "https://api.groq.com/openai/v1/chat/completions"
  MODEL      = "llama-3.3-70b-versatile"
  MAX_TOKENS    = 4096
  CACHE_TTL     = 3.hours
  CACHE_PREFIX  = "ouou_analysis"

  def initialize(symbol:)
    @symbol  = symbol.upcase
    @finnhub = FinnhubService.new
    @api_key = ENV.fetch("GROQ_API_KEY") { raise "GROQ_API_KEY not set" }
  end

  # Yields text chunks as they stream from Claude.
  # On cache hit (and force: false), yields the full cached text in one shot.
  def call(&block)
    if (cached = Rails.cache.read(cache_key))
      block.call(cached)
      return
    end

    market_data   = collect_market_data
    prompt        = build_prompt(market_data)
    momentum_md   = build_momentum_table(market_data[:yahoo][:closes], market_data[:yahoo][:volumes])
    accumulated   = +""

    stream_request(prompt) do |chunk|
      replaced = chunk.gsub("[MOMENTUM_TABLE]", "\n\n" + momentum_md + "\n\n")
      accumulated << replaced
      block.call(replaced)
    end

    if accumulated.present?
      footer = analysis_date_footer
      block.call(footer)
      Rails.cache.write(cache_key, accumulated + footer, expires_in: CACHE_TTL)
    end
  end

  private

  def stream_request(prompt, &block)
    uri     = URI(GROQ_API)
    request = build_http_request(uri, prompt)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) do |http|
      http.request(request) do |response|
        response.read_body do |chunk|
          parse_sse_chunk(chunk, &block)
        end
      end
    end
  end

  def build_http_request(uri, prompt)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["content-type"]  = "application/json"
    req.body = {
      model:      MODEL,
      max_tokens: MAX_TOKENS,
      messages:   [
        { role: "system", content: system_prompt },
        { role: "user",   content: prompt }
      ],
      stream: true
    }.to_json
    req
  end

  def parse_sse_chunk(chunk, &block)
    chunk.each_line do |line|
      next unless line.start_with?("data: ")

      data = line[6..].strip
      next if data == "[DONE]" || data.empty?

      parsed = JSON.parse(data)
      text = parsed.dig("choices", 0, "delta", "content")
      block.call(text) if text&.present?
    rescue JSON::ParserError => e
      Rails.logger.debug("[OuouAnalysis] SSE parse error: #{e.message}")
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

      ## 技術分析計算的支撐阻力位（「層級」與「價位」欄已由系統確定，必須原字不差地輸出至報告，禁止更改數字，只在「說明」欄填入你的解讀）
      #{build_sr_table(closes)}

      ## 近期新聞（過去7天）
      #{news_text.presence || '（無新聞資料）'}

      請依據歐歐的分析框架，針對 #{@symbol} 給出完整的個股分析報告。
    PROMPT
  end

  def build_momentum_table(closes, volumes)
    rows = [
      [ "5日動量",        compute_momentum(closes, 5)     ],
      [ "20日動量",       compute_momentum(closes, 20)    ],
      [ "今日成交量",     volume_vs_avg(volumes)           ],
      [ "近5日成交量趨勢", recent_volume_trend(volumes)    ]
    ]
    lines = [ "| 指標 | 數值 |", "|---|---|" ]
    rows.each { |name, val| lines << "| #{name} | #{val} |" }
    lines.join("\n")
  end

  def build_sr_table(closes)
    sr = calc_support_resistance(closes)
    rows = [
      [ "強阻力",   sr[:strong_resistance] ],
      [ "短線阻力", sr[:short_resistance]  ],
      [ "短線支撐", sr[:short_support]     ],
      [ "中線支撐", sr[:mid_support]       ],
      [ "強支撐",   sr[:strong_support]    ]
    ]
    lines = [ "| 層級 | 價位 | 說明 |", "|---|---|---|" ]
    rows.each do |name, val|
      price_str = val ? "$#{val}" : "—"
      lines << "| #{name} | #{price_str} | [說明] |"
    end
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

  def recent_volume_trend(volumes)
    return "N/A" if volumes.size < 6

    avg20  = (volumes.last(20).sum / 20.0)
    days   = volumes.last(5)
    labels = %w[D-4 D-3 D-2 D-1 今日]
    parts  = labels.zip(days).map do |label, vol|
      ratio = avg20.positive? ? (vol.to_f / avg20 * 100).round(0) : nil
      "#{label}:#{fmt_vol(vol.to_i)}#{ratio ? "(#{ratio}%)" : ''}"
    end
    parts.join(" → ")
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
    <<~'SYSTEM'
      你是歐歐 🐱，一隻招財貓投資分析師。說話帶點貓性俏皮，但分析數據絕對紮實。全程使用繁體中文。

      你的輸出必須嚴格遵照以下 Markdown 結構範本，用實際分析內容替換 [方括號] 中的佔位符。
      不得更改標題層級、不得省略任何章節、不得省略表格、不得在結尾加免責聲明。

      ---

      # 🐱 歐歐的[TICKER]（[公司全名]）投資分析報告

      ## 1. 🐱 市場立場

      歐歐立場：[🟢激進買入 / 🟡保守買入 / 🔴持幣觀望] ｜ VIX：[值] ｜
      遵循：[第一句邏輯說明]。
      [第二句補充說明，可帶貓性比喻]

      ## 2. 📊 技術面分析

      ### 動量觀察

      [MOMENTUM_TABLE]

      ### 歐歐解讀 🐾

      **[動量主題，例：5日動量 vs 20日動量的矛盾]：**

      - [解讀要點一]
      - [解讀要點二]

      ### 52週位置分析：

      - [52週位置解讀]
      - [接近高點/低點/中間的含義]

      ### 支撐與阻力位估算：

      （「層級」與「價位」欄已在 user message 中由系統計算確定，必須**原字不差**輸出，禁止更改或捏造任何數字；「說明」欄填入你的解讀；價位為「—」表示資料不足，說明欄寫「資料不足」）

      | 層級 | 價位 | 說明 |
      |---|---|---|
      | 強阻力 | [原樣輸出 user message 中的價位] | [說明] |
      | 短線阻力 | [原樣輸出 user message 中的價位] | [說明] |
      | 短線支撐 | [原樣輸出 user message 中的價位] | [說明] |
      | 中線支撐 | [原樣輸出 user message 中的價位] | [說明] |
      | 強支撐 | [原樣輸出 user message 中的價位] | [說明] |

      ## 3. 📰 催化因素

      ### 🔥 正面催化劑

      - **[催化劑標題]**：[說明]
      - **[催化劑標題]**：[說明]

      ### ⚡ 需要留意的訊號

      - [風險訊號說明]

      ## 4. 🎯 操作建議

      > ⚠️ 以下基於歐歐 [立場] 的大前提，僅適合 [適合的投資人類型]。

      ### 策略一：[策略名稱]（[標籤，例：首選 ✅]）

      | 項目 | 內容 |
      |---|---|
      | 入場觸發 | [觸發條件] |
      | 止損位 | $[價格]（[止損邏輯]） |
      | 短線目標 | $[價格]（[理由]） |
      | 中線目標 | $[價格區間]（[理由]） |
      | 成功概率 | [X]%（[前提條件]） |
      | 風報比 | [計算說明] → 約 1:[比值] |

      ### 歐歐推薦 🐾

      [總推薦說明，1–2句]

      ## 5. ⚠️ 風險提示

      ### 主要下行風險

      - [emoji] **[風險標題]**：[說明]
      - [emoji] **[風險標題]**：[說明]
      - [emoji] **[風險標題]**：[說明]

      ### 倉位建議

      > 🐱 歐歐建議：單筆最大倉位不超過總資金的 [X–Y]%

      [倉位說明，1–2句，可帶貓性比喻]

      ### 🐱 歐歐總結

      > [整體總結，2–3句，點出最核心的操作邏輯]
    SYSTEM
  end
end
