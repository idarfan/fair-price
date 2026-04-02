# frozen_string_literal: true

module Api
  module V1
    class MarginPositionsController < ApplicationController
      def index
        positions = MarginPosition.open_positions
        render json: { positions: positions.map { |p| MarginInterestService.decorate(p) } }
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

        quote = FinnhubService.new.quote(symbol)
        if quote && quote["c"].to_f > 0
          render json: { symbol: symbol, price: quote["c"].to_f }
        else
          render json: { error: "找不到此代號" }, status: :not_found
        end
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
          :sell_price, :status, :opened_on, :closed_on, :position
        )
      end
    end
  end
end
