# frozen_string_literal: true

module HallOfFame
  # 標的日線收盤價（bs_model 的 S 與 σ）。唯讀呼叫既有 YahooFinanceService#chart，不讀其他功能的資料表。
  # 同一批次內每個 ticker 只抓一次。
  class UnderlyingHistory
    RANGE = "5y"
    MARKET_TIME_ZONE = "America/New_York"

    def initialize(yahoo: YahooFinanceService.new)
      @yahoo = yahoo
      @cache = {}
    end

    # 回傳 { Date => close }，依日期正序；抓不到回空 Hash。
    def closes(ticker)
      @cache[ticker] ||= begin
        chart = @yahoo.chart(ticker, range: RANGE, interval: "1d")
        zone  = ActiveSupport::TimeZone[MARKET_TIME_ZONE]
        Array(chart[:timestamps]).zip(Array(chart[:closes]))
                                 .to_h { |ts, close| [ Time.at(ts).in_time_zone(zone).to_date, close ] }
                                 .sort.to_h
      end
    end

    def close_on(ticker, date) = closes(ticker)[date]

    # 成交日「之前」的 count 個收盤（不含成交日）；不足回 nil。
    def closes_before(ticker, date, count)
      prior = closes(ticker).select { |d, _| d < date }.values
      prior.size >= count ? prior.last(count) : nil
    end
  end
end
