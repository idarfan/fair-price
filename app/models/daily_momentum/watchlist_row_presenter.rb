# frozen_string_literal: true

module DailyMomentum
  # Computes display values for a single watchlist row.
  # Extracts range-bar percentage calculations from WatchlistRowComponent.
  class WatchlistRowPresenter
    attr_reader :symbol, :name, :price, :change, :change_pct,
                :volume, :day_high, :day_low, :high_52w, :low_52w

    def initialize(symbol:, name: nil, price: nil, change: nil, change_pct: nil,
                   volume: nil, day_high: nil, day_low: nil, high_52w: nil, low_52w: nil)
      @symbol     = symbol
      @name       = name
      @price      = price
      @change     = change
      @change_pct = change_pct
      @volume     = volume
      @day_high   = day_high
      @day_low    = day_low
      @high_52w   = high_52w
      @low_52w    = low_52w
    end

    def has_day_range?
      @day_high && @day_low && @day_high > @day_low
    end

    def has_52w_range?
      @high_52w && @low_52w
    end

    # Returns 0-100 position of current price within [low, high], or nil.
    def range_position_pct(low, high)
      range = high - low
      return nil unless range > 0 && @price

      ((@price - low) / range * 100).clamp(0, 100).round(1)
    end

    def day_range_pct
      return nil unless has_day_range?

      range_position_pct(@day_low, @day_high)
    end

    def range_52w_pct
      return nil unless has_52w_range?

      range_position_pct(@low_52w, @high_52w)
    end
  end
end
