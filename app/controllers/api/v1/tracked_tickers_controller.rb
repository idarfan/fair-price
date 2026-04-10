# frozen_string_literal: true

class Api::V1::TrackedTickersController < ApplicationController
  def index
    tickers = TrackedTicker.order(:symbol).map { |t| serialize_ticker(t) }
    render json: tickers
  end

  def create
    symbol = params[:symbol].to_s.upcase.strip
    return render json: { error: "symbol 必填" }, status: :unprocessable_entity if symbol.blank?

    ticker = TrackedTicker.find_or_initialize_by(symbol: symbol)
    ticker.active = true

    if ticker.save
      render json: serialize_ticker(ticker), status: ticker.previously_new_record? ? :created : :ok
    else
      render json: { error: ticker.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def update
    ticker = TrackedTicker.find(params[:id])
    if ticker.update(active: params[:active])
      render json: serialize_ticker(ticker)
    else
      render json: { error: ticker.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    TrackedTicker.find(params[:id]).destroy!
    head :no_content
  end

  private

  def serialize_ticker(ticker)
    {
      id:                 ticker.id,
      symbol:             ticker.symbol,
      name:               ticker.name,
      active:             ticker.active,
      last_snapshot_date: ticker.last_snapshot_date
    }
  end
end
