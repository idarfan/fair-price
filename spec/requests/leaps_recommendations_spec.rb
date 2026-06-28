# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /leaps", type: :request do
  let(:symbol) { "NOK" }

  let(:fake_candidates) do
    [
      {
        expiration_date: Date.new(2027, 1, 15), dte: 202,
        strike: 10.0, delta: 0.78,
        open_interest: 72_921, volume: 431,
        bid: 3.10, ask: 3.30, mid: 3.20,
        iv: 0.76, vega: 0.0134, itm_probability: 0.82,
        vol_oi_ratio: 0.006, underlying_price: 13.08,
        liquidity_tier: "充足", no_recent_volume_warning: false,
        time_value_pct: 0.025, bid_ask_spread_pct: 0.062
      }
    ]
  end

  let(:fake_flow_panel) do
    {
      status: :ok, date: Date.current,
      call_premium_total: 500_000, put_premium_total: 200_000,
      large_orders: [], highlighted_trades: [], aggregate: {}
    }
  end

  # ── 1. 空白頁（未輸入 symbol） ────────────────────────────────────────────

  describe "without symbol" do
    it "returns 200 and renders the search form" do
      get "/leaps"
      expect(response).to have_http_status(:ok)
    end

    it "does not call either service" do
      expect(LeapsRankingService).not_to receive(:new)
      expect(LeapsOptionsFlowPanelService).not_to receive(:new)
      get "/leaps"
    end
  end

  # ── 2. symbol 有值但 DB 沒有 fresh 資料 ──────────────────────────────────

  describe "with symbol, no fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
    end

    it "returns 200" do
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end

    it "does not call either service" do
      expect(LeapsRankingService).not_to receive(:new)
      expect(LeapsOptionsFlowPanelService).not_to receive(:new)
      get "/leaps", params: { symbol: symbol }
    end
  end

  # ── 3. 有 fresh 資料：兩個 service 都必須被正確呼叫 ──────────────────────
  #
  # 這組測試是防止「LeapsOptionsFlowPanelService.new 少傳 ranked_candidates」
  # 這種 regression（cf. 2026-06-28 教訓 17）。
  # 驗證重點：LeapsOptionsFlowPanelService.new 的第二個引數必須是
  # LeapsRankingService 回傳的 candidates 陣列，不能是 nil 或被省略。

  describe "with fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)

      ranking_svc = instance_double(LeapsRankingService, call: fake_candidates)
      allow(LeapsRankingService).to receive(:new).with(symbol).and_return(ranking_svc)

      flow_svc = instance_double(LeapsOptionsFlowPanelService, call: fake_flow_panel)
      allow(LeapsOptionsFlowPanelService)
        .to receive(:new).with(symbol, fake_candidates).and_return(flow_svc)
    end

    it "returns 200" do
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end

    it "calls LeapsRankingService with the symbol" do
      expect(LeapsRankingService).to receive(:new).with(symbol).and_call_original
      allow_any_instance_of(LeapsRankingService).to receive(:call).and_return(fake_candidates)
      get "/leaps", params: { symbol: symbol }
    end

    it "passes ranked_candidates from LeapsRankingService into LeapsOptionsFlowPanelService" do
      # This is the regression guard: new(symbol, candidates) not new(symbol)
      expect(LeapsOptionsFlowPanelService)
        .to receive(:new).with(symbol, fake_candidates)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: fake_flow_panel))
      get "/leaps", params: { symbol: symbol }
    end

    it "renders candidate rows in the response body" do
      get "/leaps", params: { symbol: symbol }
      expect(response.body).to include("LEAPS 候選排行")
    end
  end

  # ── 4. job_status=session_expired 帶回（Barchart 過期）────────────────────

  describe "job_status=session_expired with fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).and_return(
        instance_double(LeapsRankingService, call: [])
      )
      allow(LeapsOptionsFlowPanelService).to receive(:new).and_return(
        instance_double(LeapsOptionsFlowPanelService, call: { status: :no_data, date: Date.current })
      )
    end

    it "returns 200 and includes the session-expired warning" do
      get "/leaps", params: { symbol: symbol, job_status: "session_expired" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Barchart 登入已過期")
    end
  end
end
