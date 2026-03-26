# frozen_string_literal: true

# 計算歷史波動率排名（HV Rank），作為 IV Rank 的實用替代。
# 使用 YahooFinance 1 年日 K 線資料計算 30 天滾動 HV，
# 再算出目前 HV 在過去 1 年的百分位數。
class IvRankService
  WINDOW      = 30   # 30 天滾動窗口
  TRADING_DAYS = 252  # 年化用

  def initialize(symbol)
    @symbol = symbol.upcase
  end

  # 回傳 { symbol:, iv_rank:, current_hv:, hv_high:, hv_low:, iv_comment:, peers: [] }
  def call
    closes = fetch_closes(@symbol)
    return fallback_result if closes.size < WINDOW + 10

    hvs     = rolling_hv(closes)
    current = hvs.last
    rank    = percentile_rank(hvs, current)

    peers_data = fetch_peers_rank

    {
      symbol:     @symbol,
      iv_rank:    rank.round(1),
      current_hv: (current * 100).round(1),
      hv_high:    (hvs.max * 100).round(1),
      hv_low:     (hvs.min * 100).round(1),
      iv_comment: build_comment(rank),
      peers:      peers_data
    }
  end

  private

  # 從 Yahoo Finance 取得 1 年日收盤價
  def fetch_closes(symbol)
    Rails.cache.fetch("iv_rank_closes/#{symbol}", expires_in: 30.minutes) do
      data = YahooFinanceService.new.chart(symbol, range: "1y", interval: "1d")
      data[:closes] || []
    end
  end

  # 計算 30 天滾動年化歷史波動率陣列
  def rolling_hv(closes)
    return [] if closes.size < WINDOW + 1

    log_returns = closes.each_cons(2).map { |prev, cur| Math.log(cur / prev) }

    log_returns.each_cons(WINDOW).map do |window|
      mean = window.sum / window.size
      variance = window.sum { |r| (r - mean)**2 } / (window.size - 1)
      Math.sqrt(variance * TRADING_DAYS)
    end
  end

  # 目前值在歷史分佈中的百分位數（0–100）
  def percentile_rank(values, current)
    below = values.count { |v| v < current }
    (below.to_f / values.size * 100)
  end

  # 取得同類股的 HV Rank（最多 4 檔）
  def fetch_peers_rank
    peer_symbols = fetch_peer_symbols
    return [] if peer_symbols.empty?

    peer_symbols.first(4).filter_map do |sym|
      closes = fetch_closes(sym)
      next if closes.size < WINDOW + 10

      hvs     = rolling_hv(closes)
      current = hvs.last
      rank    = percentile_rank(hvs, current)

      { symbol: sym, iv: (current * 100).round(1), iv_rank: rank.round(1) }
    end
  end

  # 透過 Finnhub /stock/peers 取得同產業股票
  def fetch_peer_symbols
    Rails.cache.fetch("peers/#{@symbol}", expires_in: 1.day) do
      api_key = ENV.fetch("FINNHUB_API_KEY", nil)
      return [] unless api_key

      resp = HTTParty.get(
        "https://finnhub.io/api/v1/stock/peers",
        query:   { symbol: @symbol, token: api_key },
        timeout: 8
      )
      return [] unless resp.success?

      peers = resp.parsed_response
      return [] unless peers.is_a?(Array)

      # 排除自身，取前 4 檔
      peers.reject { |s| s == @symbol }.first(4)
    end
  rescue StandardError => e
    Rails.logger.warn("[IvRankService] peers #{@symbol}: #{e.message}")
    []
  end

  def build_comment(rank)
    case rank
    when 0..20   then "HV Rank #{rank.round(0)} — 極低，買方策略有利（期權便宜）"
    when 20..40  then "HV Rank #{rank.round(0)} — 偏低，可考慮買方策略"
    when 40..60  then "HV Rank #{rank.round(0)} — 中性，買賣方皆可"
    when 60..80  then "HV Rank #{rank.round(0)} — 偏高，賣方策略有利"
    else              "HV Rank #{rank.round(0)} — 極高，賣方策略非常有利"
    end
  end

  def fallback_result
    {
      symbol:     @symbol,
      iv_rank:    50.0,
      current_hv: nil,
      hv_high:    nil,
      hv_low:     nil,
      iv_comment: "歷史資料不足，使用預設值",
      peers:      []
    }
  end
end
