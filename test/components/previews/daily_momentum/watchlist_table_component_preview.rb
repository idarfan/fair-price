# frozen_string_literal: true

# @label Watchlist Table
class DailyMomentum::WatchlistTableComponentPreview < Lookbook::Preview
  SAMPLE_STOCKS = [
    { symbol: "AAPL", name: "Apple Inc.",      price: 213.49, change: 2.31,  change_pct: 0.011,  volume: 55_000_000, high_52w: 237.23, low_52w: 164.08 },
    { symbol: "MSFT", name: "Microsoft Corp.", price: 415.20, change: -1.80, change_pct: -0.004, volume: 22_000_000, high_52w: 468.35, low_52w: 344.79 },
    { symbol: "NVDA", name: "NVIDIA Corp.",    price: 875.40, change: 18.60, change_pct: 0.022,  volume: 44_000_000, high_52w: 974.00, low_52w: 435.00 },
    { symbol: "TSLA", name: "Tesla Inc.",      price: 180.10, change: -3.20, change_pct: -0.017, volume: 110_000_000, high_52w: 299.29, low_52w: 138.80 },
    { symbol: "AMD",  name: "Advanced Micro",  price: 155.60, change: 1.40,  change_pct: 0.009,  volume: 60_000_000, high_52w: 227.30, low_52w: 117.30 }
  ].freeze

  # @label Full watchlist
  def default
    render DailyMomentum::WatchlistTableComponent.new(stocks: SAMPLE_STOCKS)
  end

  # @label Empty state
  def empty
    render DailyMomentum::WatchlistTableComponent.new(stocks: [])
  end
end
