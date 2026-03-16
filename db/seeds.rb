# frozen_string_literal: true

# Default watchlist (only seeds if empty)
if WatchlistItem.none?
  %w[AAPL MSFT NVDA TSLA AMD].each_with_index do |symbol, i|
    WatchlistItem.create!(symbol: symbol, position: i)
  end
  puts "Seeded #{WatchlistItem.count} watchlist items"
end
