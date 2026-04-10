# frozen_string_literal: true

class OptionPriceTrackerController < ApplicationController
  def index
    @tracked_tickers = TrackedTicker.order(:symbol).map { |t|
      {
        id:                 t.id,
        symbol:             t.symbol,
        name:               t.name,
        active:             t.active,
        last_snapshot_date: t.last_snapshot_date
      }
    }
  end
end
