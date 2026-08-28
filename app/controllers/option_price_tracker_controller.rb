# frozen_string_literal: true

class OptionPriceTrackerController < ApplicationController
  def index
    @tracked_tickers = TrackedTickerSerializer.list(TrackedTicker.order(:symbol))
  end
end
