# frozen_string_literal: true

class MomentumReportService
  def initialize(symbols: nil)
    @finnhub = FinnhubService.new
    @symbols = symbols.presence || yaml_symbols
  end

  # Returns a frozen hash with all report data
  def call
    {
      segment:    time_segment,
      et_time:    et_time_string,
      vix:        fetch_vix,
      es_change:  fetch_futures_change("ES=F"),
      nq_change:  fetch_futures_change("NQ=F"),
      stance:     nil, # derived in component
      stocks:     fetch_stocks,
      earnings:   fetch_upcoming_earnings
    }.freeze
  end

  private

  # ── Market session (Taiwan time as anchor) ──────────────────────────────
  def time_segment
    now_et = Time.now.in_time_zone("Eastern Time (US & Canada)")
    mins   = now_et.hour * 60 + now_et.min

    if    mins >= 570 && mins < 960  then :market_hours  # 09:30 – 16:00 ET
    elsif mins >= 480 && mins < 570  then :pre_market    # 08:00 – 09:30 ET
    elsif (mins >= 960 && mins < 1200) || (mins >= 0 && mins < 120) then :after_hours
    else :closed
    end
  end

  def et_time_string
    Time.now.in_time_zone("Eastern Time (US & Canada)").strftime("%H:%M")
  end

  # ── VIX ─────────────────────────────────────────────────────────────────
  def fetch_vix
    VixService.new.fetch
  end

  # ── Watchlist stocks ────────────────────────────────────────────────────
  # 每批最多 5 支平行抓取，避免同時發出過多 Finnhub 請求觸發 rate limit。
  def fetch_stocks
    @symbols.each_slice(5).flat_map do |batch|
      batch.map { |symbol| Thread.new { fetch_stock(symbol) } }
           .filter_map(&:value)
    end
  end

  def fetch_stock(symbol)
    Rails.cache.fetch("momentum_quote:#{symbol}", expires_in: 60.seconds) do
      quote = @finnhub.quote(symbol)
      next nil if quote.nil? || (quote["c"].to_f.zero? && quote["pc"].to_f.zero?)

      candle_data = fetch_candles(symbol)
      {
        symbol:     symbol,
        name:       nil,
        price:      (quote["c"].to_f.nonzero? || quote["pc"].to_f),
        change:     quote["d"].to_f,
        change_pct: quote["dp"].to_f / 100.0,
        volume:     candle_data[:volume],
        day_high:   quote["h"].to_f.nonzero?,
        day_low:    quote["l"].to_f.nonzero?,
        high_52w:   candle_data[:high_52w],
        low_52w:    candle_data[:low_52w]
      }
    end
  end

  def fetch_futures_change(symbol)
    YahooFinanceService.new.chart(symbol, range: "1d", interval: "1d")[:change_pct]
  rescue StandardError => e
    Rails.logger.warn("[MomentumReport] Futures #{symbol} failed: #{e.message}")
    nil
  end

  def fetch_candles(symbol)
    result = YahooFinanceService.new.chart(symbol, range: "1y")
    { high_52w: result[:high_52w], low_52w: result[:low_52w], volume: result[:volume] }
  end

  # ── Earnings calendar (next 7 days) ─────────────────────────────────────
  def fetch_upcoming_earnings
    from_date = Date.current.to_s
    to_date   = (Date.current + 7).to_s
    items     = @finnhub.earnings_calendar(from_date: from_date, to_date: to_date)
    items.first(6).map do |e|
      { symbol: e["symbol"], date: e["date"] }
    end
  rescue StandardError => e
    Rails.logger.warn("[MomentumReport] Earnings fetch failed: #{e.message}")
    []
  end

  def yaml_symbols
    YAML.load_file(Rails.root.join("config/watchlist.yml")).fetch("symbols", [])
  rescue Errno::ENOENT
    []
  end
end
