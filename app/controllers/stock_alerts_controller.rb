# frozen_string_literal: true

class StockAlertsController < ApplicationController
  before_action :set_alert, only: %i[edit update destroy toggle toggle_condition]

  def index
    @alerts = PriceAlert.order(:position, :id)
    @market_data = fetch_market_data(@alerts.map(&:symbol).uniq)
  end

  def new
    @alert = PriceAlert.new
  end

  def create
    @alert = PriceAlert.new(alert_params)
    if @alert.save
      redirect_to watchlist_alerts_path, notice: "已建立 #{@alert.symbol} 的到價通知"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @alert.update(alert_params)
      redirect_to watchlist_alerts_path, notice: "已更新 #{@alert.symbol} 的設定"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @alert.destroy
    redirect_to watchlist_alerts_path, notice: "已刪除通知"
  end

  def toggle
    @alert.update!(active: !@alert.active)
    redirect_to watchlist_alerts_path
  end

  def toggle_condition
    new_condition = @alert.condition == "above" ? "below" : "above"
    @alert.update!(condition: new_condition)
    redirect_to watchlist_alerts_path
  end

  def reorder
    params[:ids]&.each_with_index do |id, index|
      PriceAlert.where(id: id.to_i).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  private

  def set_alert
    @alert = PriceAlert.find(params[:id])
  end

  def alert_params
    params.require(:price_alert).permit(:symbol, :target_price, :condition, :notes)
  end

  def fetch_market_data(symbols)
    return {} if symbols.empty?

    service = FinnhubService.new
    data    = {}
    mutex   = Mutex.new

    threads = symbols.map do |symbol|
      Thread.new do
        quote = Rails.cache.fetch("fh/quote/#{symbol}", expires_in: 90.seconds) { service.quote(symbol) }
        mutex.synchronize { data[symbol] = quote if quote }
      end
    end
    threads.each(&:join)
    data
  rescue StandardError => e
    Rails.logger.error("[StockAlerts] Market data fetch failed: #{e.message}")
    {}
  end
end
