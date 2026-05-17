# frozen_string_literal: true

# Default watchlist (only seeds if empty)
if WatchlistItem.none?
  %w[AAPL MSFT NVDA TSLA AMD].each_with_index do |symbol, i|
    WatchlistItem.create!(symbol: symbol, position: i)
  end
  puts "Seeded #{WatchlistItem.count} watchlist items"
end

[
  { symbol: 'QQQ',  group_tag: 'index' },
  { symbol: 'SPY',  group_tag: 'index' },
  { symbol: 'IWM',  group_tag: 'index' },
  { symbol: 'SQQQ', group_tag: 'leveraged' },
  { symbol: 'TQQQ', group_tag: 'leveraged' },
  { symbol: 'GLD',  group_tag: 'macro' },
  { symbol: 'TLT',  group_tag: 'macro' }
].each do |attrs|
  IvWatchlist.find_or_create_by(symbol: attrs[:symbol]).update(attrs)
end
puts "Seeded #{IvWatchlist.count} IV watchlist items"
