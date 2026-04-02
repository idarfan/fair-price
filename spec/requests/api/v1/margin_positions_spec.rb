# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::MarginPositions", type: :request do
  let(:json) { JSON.parse(response.body) }

  describe "GET /api/v1/margin_positions" do
    before { create_list(:margin_position, 3, symbol: "AAPL") }

    it "returns open positions with computed fields" do
      get "/api/v1/margin_positions"
      expect(response).to have_http_status(:ok)
      expect(json["positions"].length).to eq(3)
      expect(json["positions"].first).to include(
        "symbol", "balance", "annual_rate", "days_held", "accrued_interest", "next_charge_date"
      )
    end

    it "excludes closed positions" do
      create(:margin_position, :closed, symbol: "TSLA")
      get "/api/v1/margin_positions"
      symbols = json["positions"].map { |p| p["symbol"] }
      expect(symbols).not_to include("TSLA")
    end
  end

  describe "POST /api/v1/margin_positions" do
    let(:valid_params) do
      {
        margin_position: {
          symbol:    "NVDA",
          buy_price: 900.0,
          shares:    10.0,
          opened_on: Date.current.to_s
        }
      }
    end

    it "creates a new position" do
      expect {
        post "/api/v1/margin_positions", params: valid_params
      }.to change(MarginPosition, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["position"]["symbol"]).to eq("NVDA")
    end

    it "returns errors for invalid params" do
      post "/api/v1/margin_positions", params: { margin_position: { symbol: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end

  describe "PATCH /api/v1/margin_positions/:id" do
    let(:position) { create(:margin_position) }

    it "updates sell_price" do
      patch "/api/v1/margin_positions/#{position.id}",
            params: { margin_position: { sell_price: 200.0 } }
      expect(response).to have_http_status(:ok)
      expect(position.reload.sell_price.to_f).to eq(200.0)
    end
  end

  describe "DELETE /api/v1/margin_positions/:id" do
    let!(:position) { create(:margin_position) }

    it "deletes the position" do
      expect {
        delete "/api/v1/margin_positions/#{position.id}"
      }.to change(MarginPosition, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/margin_positions/:id/close" do
    let(:position) { create(:margin_position) }

    it "marks position as closed" do
      post "/api/v1/margin_positions/#{position.id}/close"
      expect(response).to have_http_status(:ok)
      expect(position.reload.status).to eq("closed")
      expect(position.reload.closed_on).to eq(Date.current)
    end
  end

  describe "GET /api/v1/margin_positions/price_lookup" do
    it "returns 400 for missing symbol" do
      get "/api/v1/margin_positions/price_lookup", params: { symbol: "" }
      expect(response).to have_http_status(:bad_request)
    end

    it "returns price, 52-week range and fair value estimate" do
      stock_data = {
        name: "Apple Inc.", current_price: 195.5,
        day_low: 193.0, day_high: 197.0,
        fifty_two_week_low: 150.0, fifty_two_week_high: 250.0,
        sector: "Technology", eps_ttm: 6.5, forward_eps: 7.0,
        book_value: 4.0, roe: 0.15, dividend_rate: 0.0,
        free_cashflow: 90_000_000_000, total_revenue: 380_000_000_000,
        ebitda: 120_000_000_000, total_debt: 100_000_000_000,
        total_cash: 50_000_000_000, earnings_growth: 0.1,
        revenue_growth: 0.08, earnings_quarterly_growth: 0.1,
        shares_outstanding: 15_400_000_000, analyst_consensus: nil,
        symbol: "AAPL", exchange: "NASDAQ", currency: "USD",
        financial_currency: "USD", currency_note: nil,
        industry: "Technology", stock_type: nil
      }
      allow(StockDataService).to receive(:fetch).with("AAPL").and_return(stock_data)
      yf_double = instance_double(YahooFinanceService,
        chart: { low_52w: 150.0, high_52w: 250.0 })
      allow(YahooFinanceService).to receive(:new).and_return(yf_double)
      get "/api/v1/margin_positions/price_lookup", params: { symbol: "AAPL" }
      expect(response).to have_http_status(:ok)
      expect(json["price"]).to eq(195.5)
      expect(json["day_low"]).to eq(193.0)
      expect(json["day_high"]).to eq(197.0)
      expect(json["week52_low"]).to eq(150.0)
      expect(json["week52_high"]).to eq(250.0)
      expect(json).to have_key("fair_value_low")
      expect(json).to have_key("fair_value_high")
    end

    it "returns 404 for unknown symbol" do
      allow(StockDataService).to receive(:fetch).and_raise(StockDataService::NotFoundError)
      get "/api/v1/margin_positions/price_lookup", params: { symbol: "ZZZZ" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
