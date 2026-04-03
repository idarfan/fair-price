# frozen_string_literal: true

class PortfoliosController < ApplicationController
  def index
    @holdings = Portfolio.ordered
    symbols   = @holdings.map(&:symbol).uniq
    @quotes   = fetch_quotes(symbols)
  end

  def create
    @holding = Portfolio.new(portfolio_params.merge(position: Portfolio.next_position))
    if @holding.save
      redirect_to portfolios_path, notice: "已新增 #{@holding.symbol}"
    else
      redirect_to portfolios_path, alert: @holding.errors.full_messages.join(", ")
    end
  end

  def update
    @holding = Portfolio.find(params[:id])
    if @holding.update(portfolio_params)
      redirect_to portfolios_path, notice: "已更新"
    else
      redirect_to portfolios_path, alert: @holding.errors.full_messages.join(", ")
    end
  end

  def destroy
    Portfolio.find(params[:id]).destroy
    redirect_to portfolios_path, notice: "已刪除"
  end

  def ocr_import
    file = params[:image]
    return redirect_to(portfolios_path, alert: "請選擇圖片檔案") if file.blank?

    holdings = PortfolioOcrService.new(file).call
    return redirect_to(portfolios_path, alert: "無法從圖片辨識持股資料，請確認圖片清晰度") if holdings.empty?

    Portfolio.transaction do
      Portfolio.delete_all
      holdings.each_with_index do |h, idx|
        Portfolio.create!(
          symbol:    h[:symbol],
          shares:    h[:shares],
          unit_cost: h[:unit_cost],
          position:  idx
        )
      end
    end

    redirect_to portfolios_path, notice: "✅ 已從圖片匯入 #{holdings.size} 筆持股"
  rescue StandardError => e
    redirect_to portfolios_path, alert: "匯入失敗：#{e.message}"
  end

  def quotes
    symbols = Portfolio.pluck(:symbol).uniq
    render json: fetch_quotes(symbols)
  end

  def ownership
    symbol = params[:symbol].to_s.upcase.gsub(/[^A-Z0-9.\-]/, "")
    return render json: { error: "invalid symbol" }, status: 422 if symbol.blank?

    data = YahooFinanceService.new.holders(symbol) ||
           SecEdgarService.new.holders(symbol)     ||
           { summary: nil, top_holders: [], source: nil }
    render json: data
  end

  def reorder
    ids = params[:ids] || []
    ids.each_with_index do |id, idx|
      Portfolio.where(id: id).update_all(position: idx) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  private

  def portfolio_params
    params.require(:portfolio).permit(:symbol, :shares, :unit_cost, :sell_price)
  end

  def fetch_quotes(symbols)
    finnhub  = FinnhubService.new
    mutex    = Mutex.new
    result   = {}
    threads  = symbols.map do |sym|
      Thread.new do
        data = finnhub.quote(sym)
        mutex.synchronize { result[sym] = data }
      rescue StandardError => e
        Rails.logger.warn("[Portfolio] quote #{sym}: #{e.message}")
        mutex.synchronize { result[sym] = nil }
      end
    end
    threads.each(&:join)
    result
  end
end
