# frozen_string_literal: true

# 從 SEC EDGAR 全文搜尋取得持有特定股票的機構（13F-HR 申報）
# 資料為季報，僅提供機構名稱與申報日期，無持股百分比。
class SecEdgarService
  EFTS_URL = "https://efts.sec.gov/LATEST/search-index"
  # SEC 要求 User-Agent 包含聯絡資訊
  HEADERS  = { "User-Agent" => "FairPrice fairprice@localhost" }.freeze

  # Returns { summary: nil, top_holders: [...], source: "SEC EDGAR (13F 季報)" } or nil
  def holders(symbol)
    from_date = (Date.today - 120).strftime("%Y-%m-%d")
    to_date   = Date.today.strftime("%Y-%m-%d")

    response = HTTParty.get(
      EFTS_URL,
      query:   {
        q:         "\"#{symbol}\"",
        forms:     "13F-HR",
        dateRange: "custom",
        startdt:   from_date,
        enddt:     to_date
      },
      headers: HEADERS,
      timeout: 15
    )

    unless response.success?
      Rails.logger.warn("[SecEdgar] holders #{symbol} HTTP #{response.code}")
      return nil
    end

    hits = response.parsed_response.dig("hits", "hits") || []
    return nil if hits.empty?

    seen        = {}
    top_holders = []
    hits.each do |hit|
      src = hit["_source"] || {}
      # display_names 格式："Vanguard Group Inc  (CIK 0000102909)"
      raw_name = Array(src["display_names"]).first.to_s
      name     = raw_name.gsub(/\s*\(CIK\s*\d+\)\s*$/, "").strip
      next if name.empty? || seen[name]

      seen[name] = true
      top_holders << {
        name:        name,
        pct_held:    nil,
        value:       nil,
        report_date: src["period_ending"] || src["file_date"]
      }
      break if top_holders.size >= 10
    end

    return nil if top_holders.empty?

    { summary: nil, top_holders: top_holders, source: "SEC EDGAR (13F 季報)" }
  rescue StandardError => e
    Rails.logger.warn("[SecEdgar] holders #{symbol} failed: #{e.message}")
    nil
  end
end
