# frozen_string_literal: true

require "open3"

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

  # POST /api/v1/tracked_tickers/:id/collect
  # 立即執行 Python 蒐集器，抓取該代號的期權快照
  def collect
    ticker = TrackedTicker.find(params[:id])
    python = Rails.root.join("scripts/venv/bin/python3").to_s
    script = Rails.root.join("scripts/options_collector.py").to_s

    _output, status = Open3.capture2e(python, script, "--symbols", ticker.symbol)

    if status.success?
      ticker.reload
      render json: serialize_ticker(ticker)
    else
      render json: { error: "#{ticker.symbol} 期權資料抓取失敗，請確認 Python 環境" },
             status: :unprocessable_entity
    end
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
