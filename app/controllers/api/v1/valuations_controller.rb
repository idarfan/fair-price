module Api
  module V1
    class ValuationsController < ApplicationController
      def show
        ticker        = params[:ticker].to_s.upcase.strip
        discount_rate = parse_discount_rate(params[:discount_rate])

        unless valid_ticker?(ticker)
          render json: { error: "無效的股票代號" }, status: :unprocessable_entity
          return
        end

        stock_data    = StockDataService.fetch(ticker)
        valuation     = ValuationService.analyze(stock_data, discount_rate:)
        exchange_rate = ExchangeRateService.usd_twd

        render json: {
          stock:      stock_data,
          valuation:  valuation,
          usd_twd:    exchange_rate,
          fetched_at: Time.current.iso8601
        }
      rescue StockDataService::NotFoundError => e
        render json: { error: e.message }, status: :not_found
      rescue => e
        render json: { error: "查詢失敗：#{e.message}" }, status: :unprocessable_entity
      end

      private

      def parse_discount_rate(raw)
        rate = raw.to_f
        return 0.10 if rate <= 0 || rate > 50

        rate > 1 ? rate / 100.0 : rate
      end

      def valid_ticker?(ticker)
        ticker.match?(/\A[A-Z0-9.\-]{1,10}\z/)
      end
    end
  end
end
