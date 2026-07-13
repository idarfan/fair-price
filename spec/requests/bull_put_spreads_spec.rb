# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bull Put Spread (BPUS)", type: :request do
  let(:symbol) { "RKLB" }
  let(:expiration) { "2026-08-21-m" }

  # test 環境的 cache_store 是 null_store（config/environments/test.rb），
  # 寫入即丟棄——這裡暫時換成真的 MemoryStore，讓 job kickoff 的
  # exist?/read/write 短路邏輯可以被實際測到，測完換回去。
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  # ── GET /bpus ──────────────────────────────────────────────────────────────

  describe "GET /bpus" do
    it "returns 200 without a symbol and does not call any service" do
      expect(BarchartScraperService).not_to receive(:new)
      get "/bpus"
      expect(response).to have_http_status(:ok)
    end

    it "rejects an invalid symbol format without calling any service" do
      expect(BarchartScraperService).not_to receive(:new)
      get "/bpus", params: { symbol: "TOO-LONG-1" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("股票代號格式錯誤")
    end

    it "shows ready_to_fetch when symbol is valid but nothing is cached" do
      get "/bpus", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end

    it "renders cached expirations without calling BarchartScraperService" do
      Rails.cache.write("bpus_expirations_#{symbol}", {
        status: "success", expirations: [ "2026-08-21-m", "2026-09-18-m" ], underlying_price: 42.5
      })
      expect(BarchartScraperService).not_to receive(:new)
      get "/bpus", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("42.5").or include("42.50")
    end

    it "renders cached put chain when both symbol and expiration are cached" do
      Rails.cache.write("bpus_expirations_#{symbol}", {
        status: "success", expirations: [ expiration ], underlying_price: 42.5
      })
      Rails.cache.write("bpus_put_chain_#{symbol}_#{expiration}", {
        status: "success",
        rows: [ { "strike" => 40.0, "bid" => 1.1, "ask" => 1.3, "iv" => 0.5, "delta" => -0.3, "open_interest" => 100 } ],
        underlying_price: 42.5
      })
      get "/bpus", params: { symbol: symbol, expiration: expiration }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("40.00")
    end
  end

  # ── POST /bpus/fetch_expirations ─────────────────────────────────────────

  describe "POST /bpus/fetch_expirations" do
    it "returns 422 without a symbol" do
      post "/bpus/fetch_expirations", params: { symbol: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid symbol format" do
      post "/bpus/fetch_expirations", params: { symbol: "TOOLONG1" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already cached" do
      Rails.cache.write("bpus_expirations_#{symbol}", { status: "success", expirations: [], underlying_price: nil })
      expect(BpusFetchExpirationsJob).not_to receive(:perform_later)
      post "/bpus/fetch_expirations", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "returns cdp_offline without kicking off a job when CDP is unreachable" do
      allow_any_instance_of(BullPutSpreadsController).to receive(:cdp_online?).and_return(false)
      expect(BpusFetchExpirationsJob).not_to receive(:perform_later)
      post "/bpus/fetch_expirations", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("cdp_offline")
    end

    it "kicks off the job with the correct symbol argument when CDP is online and nothing is cached" do
      allow_any_instance_of(BullPutSpreadsController).to receive(:cdp_online?).and_return(true)
      expect(BpusFetchExpirationsJob).to receive(:perform_later).with(symbol, instance_of(String))
      post "/bpus/fetch_expirations", params: { symbol: symbol }, as: :json
      body = JSON.parse(response.body)
      expect(body["job_id"]).to be_present
    end
  end

  # ── POST /bpus/fetch_chain ────────────────────────────────────────────────

  describe "POST /bpus/fetch_chain" do
    it "returns 422 without an expiration" do
      post "/bpus/fetch_chain", params: { symbol: symbol, expiration: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid symbol format" do
      post "/bpus/fetch_chain", params: { symbol: "TOOLONG1", expiration: expiration }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already cached" do
      Rails.cache.write("bpus_put_chain_#{symbol}_#{expiration}", { status: "success", rows: [], underlying_price: nil })
      expect(BpusFetchChainJob).not_to receive(:perform_later)
      post "/bpus/fetch_chain", params: { symbol: symbol, expiration: expiration }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "kicks off the job with the correct symbol and expiration keyword-equivalent arguments" do
      allow_any_instance_of(BullPutSpreadsController).to receive(:cdp_online?).and_return(true)
      expect(BpusFetchChainJob).to receive(:perform_later).with(symbol, expiration, instance_of(String))
      post "/bpus/fetch_chain", params: { symbol: symbol, expiration: expiration }, as: :json
      body = JSON.parse(response.body)
      expect(body["job_id"]).to be_present
    end
  end

  # ── GET /bpus/status ──────────────────────────────────────────────────────

  describe "GET /bpus/status" do
    it "returns not_found for an unknown job_id" do
      get "/bpus/status", params: { job_id: "deadbeef" }
      expect(JSON.parse(response.body)["status"]).to eq("not_found")
    end

    it "returns the cached job status" do
      Rails.cache.write("bpus_job_deadbeef", { status: "success", errors: [] })
      get "/bpus/status", params: { job_id: "deadbeef" }
      expect(JSON.parse(response.body)["status"]).to eq("success")
    end

    it "returns 422 without a job_id" do
      get "/bpus/status"
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ── POST /bpus/calculate ──────────────────────────────────────────────────
  # 這組測試對應 bpus.md §8.1「service 初始化參數完整性」：驗證 controller 把
  # 正確的四個關鍵字參數傳進 BullPutSpreadCalculatorService，不是少傳或傳錯欄位。

  describe "POST /bpus/calculate" do
    it "calls BullPutSpreadCalculatorService with the correct keyword arguments" do
      expect(BullPutSpreadCalculatorService).to receive(:new).with(
        short_strike: 75.0, short_bid: 3.2, long_strike: 70.0, long_ask: 1.7
      ).and_call_original

      post "/bpus/calculate", params: {
        short_strike: "75", short_bid: "3.2", long_strike: "70", long_ask: "1.7"
      }, as: :json
    end

    it "returns the full calculation payload for a normal credit spread" do
      post "/bpus/calculate", params: {
        short_strike: "75", short_bid: "3.2", long_strike: "70", long_ask: "1.7"
      }, as: :json

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["net_credit"]).to eq(150.0)
      expect(body["max_loss"]).to eq(350.0)
      expect(body["breakeven"]).to eq(73.5)
      expect(body["warning"]).to be_nil
    end

    it "flags a debit combination without raising" do
      post "/bpus/calculate", params: {
        short_strike: "75", short_bid: "1.0", long_strike: "70", long_ask: "1.5"
      }, as: :json

      body = JSON.parse(response.body)
      expect(body["warning"]).to eq("debit")
      expect(body["roc"]).to be_nil
    end

    it "returns 422 when a parameter is missing" do
      post "/bpus/calculate", params: { short_strike: "75", short_bid: "3.2", long_strike: "70" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when a parameter is not numeric" do
      post "/bpus/calculate", params: {
        short_strike: "abc", short_bid: "3.2", long_strike: "70", long_ask: "1.7"
      }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
