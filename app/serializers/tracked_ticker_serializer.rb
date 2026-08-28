# frozen_string_literal: true

# TrackedTicker 的共用序列化。
#
# 過去 Api::V1::TrackedTickersController 與 OptionPriceTrackerController 各自
# 維護一份一模一樣的 hash，而且兩份都踩同一個 N+1：逐筆呼叫
# TrackedTicker#last_snapshot_date，每筆一次 `MAX(snapshot_date)` 查詢。
# option_snapshots 目前有 79 萬列，這個查詢不該跑 N 次。
class TrackedTickerSerializer
  # 一次 group query 取回所有代號的最新快照日期。
  def self.list(tickers)
    tickers = tickers.to_a
    return [] if tickers.empty?

    latest = OptionSnapshot.where(tracked_ticker_id: tickers.map(&:id))
                           .group(:tracked_ticker_id)
                           .maximum(:snapshot_date)

    tickers.map { |ticker| new(ticker, last_snapshot_date: latest[ticker.id]).as_json }
  end

  def self.one(ticker)
    new(ticker).as_json
  end

  def initialize(ticker, last_snapshot_date: :unset)
    @ticker = ticker
    @last_snapshot_date = last_snapshot_date
  end

  def as_json
    {
      id:                 @ticker.id,
      symbol:             @ticker.symbol,
      name:               @ticker.name,
      active:             @ticker.active,
      last_snapshot_date: last_snapshot_date
    }
  end

  private

  # 單筆序列化時沒有預先算好的值，才回頭問 model。
  def last_snapshot_date
    @last_snapshot_date == :unset ? @ticker.last_snapshot_date : @last_snapshot_date
  end
end
