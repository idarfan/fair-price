# frozen_string_literal: true

class ValuationsController < ApplicationController
  before_action :validate_ticker, only: :show

  def index
    @discount_rate = 10.0
    @ticker        = ""
  end

  def show
    ticker        = params[:ticker].to_s.upcase.strip
    discount_rate = parse_discount_rate(params[:discount_rate])

    @stock         = StockDataService.fetch(ticker)
    @analysis      = ValuationService.analyze(@stock, discount_rate:)
    @ticker        = ticker
    @discount_rate = (discount_rate * 100).round(1)
  rescue StockDataService::ConfigError => e
    flash.now[:alert_type] = :warning
    flash.now[:error]      = e.message
    @ticker        = ticker
    @discount_rate = 10.0
    render :index
  rescue StockDataService::NotFoundError => e
    flash.now[:alert_type] = :error
    flash.now[:error]      = e.message
    @ticker        = ticker
    @discount_rate = (params[:discount_rate]&.to_f || 10.0)
    render :index
  end

  private

  def validate_ticker
    ticker = params[:ticker].to_s
    unless ticker.match?(/\A[A-Za-z0-9.\-]{1,10}\z/)
      flash[:error] = "無效的股票代號"
      redirect_to root_path
    end
  end

  def parse_discount_rate(raw)
    rate = raw.to_f
    return 0.10 if rate <= 0 || rate > 50

    rate > 1 ? rate / 100.0 : rate
  end
end
