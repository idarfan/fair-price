# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Technical Dashboard", type: :request do
  let(:symbol)     { "MU" }
  let(:expiration) { "2026-08-21-m" }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  # ── POST /technical_dashboard/analyze — CDP 離線時直接擋下不送 job ─────────

  describe "POST /technical_dashboard/analyze" do
    it "returns 422 without a symbol" do
      post "/technical_dashboard/analyze", params: { symbol: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already fresh" do
      FetchLog.create!(symbol: symbol, status: "success", fetch_type: "technical", fetched_at: Time.current)
      expect(TechnicalDashboardAnalyzeJob).not_to receive(:perform_later)
      post "/technical_dashboard/analyze", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "returns cdp_offline without kicking off a job when CDP is unreachable" do
      allow_any_instance_of(TechnicalDashboardsController).to receive(:cdp_online?).and_return(false)
      expect(TechnicalDashboardAnalyzeJob).not_to receive(:perform_later)
      post "/technical_dashboard/analyze", params: { symbol: symbol }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("cdp_offline")
    end

    it "kicks off the job when CDP is online and nothing is fresh" do
      allow_any_instance_of(TechnicalDashboardsController).to receive(:cdp_online?).and_return(true)
      expect(TechnicalDashboardAnalyzeJob).to receive(:perform_later).with(symbol, kind_of(String), instance_of(String))
      post "/technical_dashboard/analyze", params: { symbol: symbol }, as: :json
      expect(JSON.parse(response.body)["job_id"]).to be_present
    end
  end

  # ── POST /technical_dashboard/fetch_max_pain — CDP 離線時直接擋下不送 job ──

  describe "POST /technical_dashboard/fetch_max_pain" do
    it "returns 422 without a symbol or expiration" do
      post "/technical_dashboard/fetch_max_pain", params: { symbol: symbol, expiration: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns ready without kicking off a job when already cached" do
      MaxPainSnapshot.create!(
        symbol: symbol, snapshot_date: Date.today, expiration: expiration,
        strikes_filter: "show_all", volume_oi_filter: "open_interest", fetched_at: Time.current
      )
      expect(TechnicalDashboardMaxPainFetchJob).not_to receive(:perform_later)
      post "/technical_dashboard/fetch_max_pain", params: { symbol: symbol, expiration: expiration }, as: :json
      expect(JSON.parse(response.body)["status"]).to eq("ready")
    end

    it "returns cdp_offline without kicking off a job when CDP is unreachable" do
      allow_any_instance_of(TechnicalDashboardsController).to receive(:cdp_online?).and_return(false)
      expect(TechnicalDashboardMaxPainFetchJob).not_to receive(:perform_later)
      post "/technical_dashboard/fetch_max_pain", params: { symbol: symbol, expiration: expiration }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("cdp_offline")
    end

    it "kicks off the job when CDP is online and nothing is cached" do
      allow_any_instance_of(TechnicalDashboardsController).to receive(:cdp_online?).and_return(true)
      expect(TechnicalDashboardMaxPainFetchJob)
        .to receive(:perform_later).with(symbol, expiration, "show_all", "open_interest", instance_of(String))
      post "/technical_dashboard/fetch_max_pain", params: { symbol: symbol, expiration: expiration }, as: :json
      expect(JSON.parse(response.body)["job_id"]).to be_present
    end
  end

  # ── GET /technical_dashboard — 顯示 cdp_offline 錯誤訊息 ───────────────────

  describe "GET /technical_dashboard with job_status=cdp_offline" do
    it "shows the CDP offline message" do
      get "/technical_dashboard", params: { symbol: symbol, job_status: "cdp_offline" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CDP 未連線")
      expect(response.body).to include("wsl --shutdown")
    end
  end
end
