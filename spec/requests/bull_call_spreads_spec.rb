# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bull Call Vertical Spread (BCVS)", type: :request do
  let(:symbol)     { "RKLB" }
  let(:expiration) { "2026-08-21-m" }

  # test 環境的 cache_store 是 null_store（config/environments/test.rb），
  # 寫入即丟棄——這裡暫時換成真的 MemoryStore，讓 job kickoff 的
  # exist?/read/write 短路邏輯可以被實際測到，測完換回去（比照 bpus 既有做法）。
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  # ── GET /bcvs ────────────────────────────────────────────────────────────

  describe "GET /bcvs" do
    it "returns 200 without a symbol and does not call any service" do
      expect(BarchartScraperService).not_to receive(:new)
      get "/bcvs"
      expect(response).to have_http_status(:ok)
    end

    it "rejects an invalid symbol format without calling any service" do
      expect(BarchartScraperService).not_to receive(:new)
      get "/bcvs", params: { symbol: "TOO-LONG-1" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("股票代號格式錯誤")
    end

    it "shows ready_to_fetch when symbol is valid but nothing is cached" do
      get "/bcvs", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end

    it "renders cached expirations without calling BarchartScraperService" do
      BcvsCacheService.upsert_expirations!(symbol, expirations: [ expiration ], underlying_price: 67.62)
      expect(BarchartScraperService).not_to receive(:new)
      get "/bcvs", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end

    it "renders cached call chain when both symbol and expiration are cached" do
      BcvsCacheService.upsert_expirations!(symbol, expirations: [ expiration ], underlying_price: 67.62)
      BcvsCacheService.upsert_chain!(
        symbol, expiration,
        strikes: [ { "strike" => 70.0, "bid" => 7.45, "ask" => 8.00, "open_interest" => 399 } ],
        underlying_price: 67.62
      )
      get "/bcvs", params: { symbol: symbol, expiration: expiration }
      expect(response).to have_http_status(:ok)
    end
  end

  # ── POST /bcvs/fetch_expirations ────────────────────────────────────────

  describe "POST /bcvs/fetch_expirations" do
    it "returns 422 without a symbol" do
      post "/bcvs/fetch_expirations", params: { symbol: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid symbol format" do
      post "/bcvs/fetch_expirations", params: { symbol: "TOOLONG1" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already fresh in Postgres" do
      BcvsCacheService.upsert_expirations!(symbol, expirations: [], underlying_price: nil)
      expect(BcvsFetchExpirationsJob).not_to receive(:perform_later)
      post "/bcvs/fetch_expirations", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "returns cdp_offline without kicking off a job when CDP is unreachable" do
      allow_any_instance_of(BullCallSpreadsController).to receive(:cdp_online?).and_return(false)
      expect(BcvsFetchExpirationsJob).not_to receive(:perform_later)
      post "/bcvs/fetch_expirations", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("cdp_offline")
    end

    it "kicks off the job with the correct symbol argument when CDP is online and nothing is cached" do
      allow_any_instance_of(BullCallSpreadsController).to receive(:cdp_online?).and_return(true)
      expect(BcvsFetchExpirationsJob).to receive(:perform_later).with(symbol, instance_of(String))
      post "/bcvs/fetch_expirations", params: { symbol: symbol }, as: :json
      body = JSON.parse(response.body)
      expect(body["job_id"]).to be_present
    end
  end

  # ── POST /bcvs/fetch_chain ──────────────────────────────────────────────

  describe "POST /bcvs/fetch_chain" do
    it "returns 422 without an expiration" do
      post "/bcvs/fetch_chain", params: { symbol: symbol, expiration: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid symbol format" do
      post "/bcvs/fetch_chain", params: { symbol: "TOOLONG1", expiration: expiration }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already fresh in Postgres" do
      BcvsCacheService.upsert_chain!(symbol, expiration, strikes: [], underlying_price: nil)
      expect(BcvsFetchChainJob).not_to receive(:perform_later)
      post "/bcvs/fetch_chain", params: { symbol: symbol, expiration: expiration }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "kicks off the job with the correct symbol and expiration arguments" do
      allow_any_instance_of(BullCallSpreadsController).to receive(:cdp_online?).and_return(true)
      expect(BcvsFetchChainJob).to receive(:perform_later).with(symbol, expiration, instance_of(String))
      post "/bcvs/fetch_chain", params: { symbol: symbol, expiration: expiration }, as: :json
      body = JSON.parse(response.body)
      expect(body["job_id"]).to be_present
    end
  end

  # ── GET /bcvs/status ─────────────────────────────────────────────────────

  describe "GET /bcvs/status" do
    it "returns not_found for an unknown job_id" do
      get "/bcvs/status", params: { job_id: "deadbeef" }
      expect(JSON.parse(response.body)["status"]).to eq("not_found")
    end

    it "returns the cached job status" do
      Rails.cache.write("bcvs_job_deadbeef", { status: "success", errors: [] })
      get "/bcvs/status", params: { job_id: "deadbeef" }
      expect(JSON.parse(response.body)["status"]).to eq("success")
    end

    it "returns 422 without a job_id" do
      get "/bcvs/status"
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ── POST /bcvs/recommend ─────────────────────────────────────────────────

  describe "POST /bcvs/recommend" do
    it "returns 422 when required params are missing or non-numeric" do
      post "/bcvs/recommend", params: { symbol: symbol, expiration: expiration, k1: "abc", k1_ask: "8.0" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when the chain is not cached" do
      post "/bcvs/recommend", params: { symbol: symbol, expiration: expiration, k1: "70", k1_ask: "8.0" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "calls BullCallSpreadRecommenderService with the correct keyword arguments and returns three tabs" do
      strikes = [
        { "strike" => 80.0, "bid" => 2.0,  "ask" => 2.2,  "open_interest" => 50 },
        { "strike" => 82.0, "bid" => 3.0,  "ask" => 3.2,  "open_interest" => 40 },
        { "strike" => 85.0, "bid" => 2.75, "ask" => 3.0,  "open_interest" => 30 }
      ]
      BcvsCacheService.upsert_chain!(symbol, expiration, strikes: strikes, underlying_price: 75.0)

      expect(BullCallSpreadRecommenderService).to receive(:new).with(
        k1: 70.0, k1_ask: 8.0, candidates: a_kind_of(Array), k1_bid: nil
      ).and_call_original

      post "/bcvs/recommend", params: { symbol: symbol, expiration: expiration, k1: "70", k1_ask: "8.0" }, as: :json

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["tabs"].keys).to include("conservative", "balanced", "aggressive")
      conservative = body["tabs"]["conservative"]
      expect(conservative).to include("s_star", "naked_cost", "naked_breakeven", "spread_max_value")
    end

    it "passes k1_bid through when given, enabling closeout_value on the response" do
      strikes = [
        { "strike" => 80.0, "bid" => 2.0, "ask" => 2.2, "open_interest" => 50 }
      ]
      BcvsCacheService.upsert_chain!(symbol, expiration, strikes: strikes, underlying_price: 75.0)

      expect(BullCallSpreadRecommenderService).to receive(:new).with(
        k1: 70.0, k1_ask: 8.0, candidates: a_kind_of(Array), k1_bid: 7.8
      ).and_call_original

      post "/bcvs/recommend", params: {
        symbol: symbol, expiration: expiration, k1: "70", k1_ask: "8.0", k1_bid: "7.8"
      }, as: :json

      body = JSON.parse(response.body)
      expect(body["tabs"]["conservative"]["closeout_value"]).not_to be_nil
    end
  end

  # ── POST /bcvs/calculate (repair mode) ───────────────────────────────────

  describe "POST /bcvs/calculate" do
    it "calls BullCallSpreadRepairCalculatorService with the correct keyword arguments" do
      expect(BullCallSpreadRepairCalculatorService).to receive(:new).with(
        k1: 10.0, k2: 12.0, k2_bid: 0.6, basis: 6.9, k1_current_bid: nil
      ).and_call_original

      post "/bcvs/calculate", params: { k1: "10", k2: "12", k2_bid: "0.6", basis: "6.9" }, as: :json
    end

    it "returns the locked-loss warning and amount for the NOK repair example" do
      post "/bcvs/calculate", params: { k1: "10", k2: "12", k2_bid: "0.6", basis: "6.9" }, as: :json

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["warning"]).to eq("locked_loss")
      # locked_loss amount = basis - ((K2-K1) + K2_bid) = 6.9 - 2.6 = 4.3 -> $430/口
      expect(body["locked_result"]).to eq(-4.3)
      expect(body["locked_result_total"]).to eq(-430.0)
      expect(body["breakeven_basis"]).to eq(2.6)
    end

    it "returns 422 when a parameter is missing" do
      post "/bcvs/calculate", params: { k1: "10", k2: "12", k2_bid: "0.6" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when a parameter is not numeric" do
      post "/bcvs/calculate", params: { k1: "abc", k2: "12", k2_bid: "0.6", basis: "6.9" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "includes closeout figures when k1_current_bid is given" do
      post "/bcvs/calculate", params: {
        k1: "10", k2: "12", k2_bid: "0.6", basis: "6.9", k1_current_bid: "2.1"
      }, as: :json

      body = JSON.parse(response.body)
      expect(body["closeout_proceeds"]).to eq(210.0)
      expect(body["closeout_pnl"]).to eq(-480.0)
    end
  end
end
