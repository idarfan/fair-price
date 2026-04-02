# frozen_string_literal: true

module Api
  module V1
    class MarginPositionsController < ApplicationController
      def index
        open_pos   = MarginPosition.open_positions
        closed_pos = MarginPosition.closed_positions
        render json: {
          positions:        open_pos.map { |p| MarginInterestService.decorate(p) },
          closed_positions: closed_pos.map { |p| MarginInterestService.decorate(p) }
        }
      end

      def create
        position = MarginPosition.new(create_params)
        if position.save
          render json: { position: MarginInterestService.decorate(position) }, status: :created
        else
          render json: { errors: position.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        position = find_position
        if position.update(update_params)
          render json: { position: MarginInterestService.decorate(position) }
        else
          render json: { errors: position.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        find_position.destroy!
        head :no_content
      end

      def close
        position = find_position
        if position.update(status: "closed", closed_on: Date.current)
          render json: { position: MarginInterestService.decorate(position) }
        else
          render json: { errors: position.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def price_lookup
        symbol = sanitize_symbol(params[:symbol])
        unless symbol
          render json: { error: "無效的股票代號" }, status: :bad_request
          return
        end

        begin
          stock_data = StockDataService.fetch(symbol)
        rescue StockDataService::NotFoundError
          render json: { error: "找不到此代號" }, status: :not_found
          return
        rescue => e
          Rails.logger.warn("[MarginPositions#price_lookup] #{e.message}")
          render json: { error: "查詢失敗，請稍後再試" }, status: :service_unavailable
          return
        end

        # Yahoo Finance 對 NYSE ADR（如 UMC）回傳正確的 NYSE USD 52 週區間；
        # Finnhub basic_metrics 對跨掛牌股票可能回傳原始交易所（如 TWSE TWD）數據。
        yf = YahooFinanceService.new.chart(symbol)
        week52_low  = yf[:low_52w]  || stock_data[:fifty_two_week_low]
        week52_high = yf[:high_52w] || stock_data[:fifty_two_week_high]

        valuation = ValuationService.analyze(stock_data)

        render json: {
          symbol:          symbol,
          company_name:    stock_data[:name],
          price:           stock_data[:current_price],
          day_low:         stock_data[:day_low],
          day_high:        stock_data[:day_high],
          week52_low:      week52_low,
          week52_high:     week52_high,
          fair_value_low:  valuation[:fair_value_low],
          fair_value_high: valuation[:fair_value_high],
          stock_type:      valuation[:stock_type]
        }
      end

      private

      def find_position
        MarginPosition.find(params[:id])
      end

      def sanitize_symbol(s)
        cleaned = s.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10)
        cleaned.presence
      end

      def create_params
        params.require(:margin_position).permit(
          :symbol, :buy_price, :shares, :sell_price, :opened_on
        )
      end

      def update_params
        params.require(:margin_position).permit(
          :buy_price, :sell_price, :status, :opened_on, :closed_on, :position
        )
      end
    end
  end
end
