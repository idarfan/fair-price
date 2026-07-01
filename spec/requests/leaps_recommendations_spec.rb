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
      expect(response.body).to include("請先登入 Barchart 後重試")
    end
  end

  # ── 5. job_status=partial_error 帶回（抓取中途 Session 過期）──────────────

  describe "job_status=partial_error without fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
      allow(Rails.cache).to receive(:read)
        .with("leaps_last_errors_#{symbol}")
        .and_return([ "Session 在抓取到 2027-01-17 的 Options Prices 時過期，已抓到的部分可能不完整，請重新查詢" ])
    end

    it "returns 200 and includes the expired_at date in the message" do
      get "/leaps", params: { symbol: symbol, job_status: "partial_error" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2027-01-17")
      expect(response.body).to include("Session 在抓取到")
    end
  end

  describe "job_status=partial_error without fresh data — cache empty (fallback text)" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
      # no cache stub → cached_errors returns []
    end

    it "returns 200 and shows neutral fallback (not session-specific wording)" do
      get "/leaps", params: { symbol: symbol, job_status: "partial_error" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("抓取中途發生未預期錯誤")
      expect(response.body).not_to include("請重新登入 Barchart")
      expect(response.body).not_to include("wsl --shutdown")
    end
  end

  # ── 5b. job_status=partial_error WITH fresh data（重疊 UX 邏輯）──────────────

  let(:stub_candidate) do
    {
      expiration_date: Date.new(2027, 12, 17), dte: 535,
      strike: 7.0, delta: 0.875,
      open_interest: 1304, volume: 1, bid: 7.40, ask: 7.75, mid: 7.58,
      iv: 0.765, vega: 0.0311, itm_probability: 0.755, vol_oi_ratio: 0.001,
      underlying_price: 4.70, liquidity_tier: "普通",
      no_recent_volume_warning: false,
      time_value_pct: 0.098, bid_ask_spread_pct: 0.046
    }
  end

  let(:stub_recommendation) do
    pick = stub_candidate
    {
      near_term: { label: "近天期 LEAPS（DTE 364–550）", no_candidates: false,
                   pick: pick, runner_up: nil, reason: "建議到期日：2027-12-17" },
      far_term:  { label: "遠天期 LEAPS（DTE 550+）",    no_candidates: false,
                   pick: pick.merge(expiration_date: Date.new(2028, 1, 21), dte: 570), runner_up: nil, reason: "建議到期日：2028-01-21" }
    }
  end

  def stub_fresh_with_recommendation(recommendation)
    allow(LeapsOptionChainSnapshot)
      .to receive_message_chain(:for_symbol, :fresh, :exists?).and_return(true)
    allow(LeapsRankingService).to receive_message_chain(:new, :call).and_return([ stub_candidate ])
    allow(LeapsRecommendationService).to receive_message_chain(:new, :call).and_return(recommendation)
    allow(LeapsOptionsFlowPanelService).to receive_message_chain(:new, :call).and_return({ status: :no_data })
  end

  describe "job_status=partial_error WITH fresh data, expired strike does NOT overlap recommendation" do
    before do
      stub_fresh_with_recommendation(stub_recommendation)
      allow(Rails.cache).to receive(:read)
        .with("leaps_last_errors_#{symbol}")
        .and_return([ "Session 在抓取 Strike 9 的 Volatility & Greeks 時過期，已抓到的部分可能不完整，請重新查詢" ])
    end

    it "shows non-overlap banner with specific strike message" do
      get "/leaps", params: { symbol: symbol, job_status: "partial_error" }
      expect(response).to have_http_status(:ok)
      # HTML encodes & as &amp;, so check non-ambiguous fragments
      expect(response.body).to include("Strike 9")
      expect(response.body).to include("資料不完整，但不影響本次推薦")
      expect(response.body).to include("Strike 7")
      expect(response.body).not_to include("此推薦的 Vega/被指派機率資料可能不完整")
    end
  end

  describe "job_status=partial_error WITH fresh data, expired strike OVERLAPS recommendation" do
    before do
      stub_fresh_with_recommendation(stub_recommendation)
      allow(Rails.cache).to receive(:read)
        .with("leaps_last_errors_#{symbol}")
        .and_return([ "Session 在抓取 Strike 7 的 Volatility & Greeks 時過期，已抓到的部分可能不完整，請重新查詢" ])
    end

    it "shows original error banner and inline warning on recommendation card" do
      get "/leaps", params: { symbol: symbol, job_status: "partial_error" }
      expect(response).to have_http_status(:ok)
      # & is HTML-encoded as &amp; in body; match non-ambiguous fragments
      expect(response.body).to include("Session 在抓取 Strike 7")
      expect(response.body).to include("Greeks 時過期")
      expect(response.body).to include("此推薦的 Vega/被指派機率資料可能不完整")
    end
  end

  # ── 6. job_status=cdp_offline / error 帶回 ─────────────────────────────────

  describe "job_status=cdp_offline without fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
    end

    it "returns 200 and shows CDP error message" do
      get "/leaps", params: { symbol: symbol, job_status: "cdp_offline" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wsl --shutdown")
    end
  end

  describe "job_status=error without fresh data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
      allow(Rails.cache).to receive(:read)
        .with("leaps_last_errors_#{symbol}")
        .and_return(["抓取時發生系統錯誤"])
    end

    it "returns 200 and shows generic error from scrape_errors" do
      get "/leaps", params: { symbol: symbol, job_status: "error" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("抓取時發生系統錯誤")
      expect(response.body).not_to include("wsl --shutdown")
    end
  end
  # ── 7. POST /leaps/analyze — CDP 離線時直接擋下不送 job ─────────────────────

  describe "POST /leaps/analyze" do
    let(:symbol) { "NOK" }

    context "when CDP is offline" do
      before do
        allow(LeapsOptionChainSnapshot)
          .to receive_message_chain(:for_symbol, :fresh, :exists?)
          .and_return(false)
        allow_any_instance_of(LeapsRecommendationsController)
          .to receive(:cdp_online?).and_return(false)
      end

      it "returns cdp_offline status without enqueueing a job" do
        expect(ScrapeLeapsJob).not_to receive(:perform_later)
        post "/leaps/analyze", params: { symbol: symbol }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("cdp_offline")
      end
    end

    context "when CDP is online and fresh data exists" do
      before do
        allow(LeapsOptionChainSnapshot)
          .to receive_message_chain(:for_symbol, :fresh, :exists?)
          .and_return(true)
      end

      it "returns ready without enqueueing a job" do
        expect(ScrapeLeapsJob).not_to receive(:perform_later)
        post "/leaps/analyze", params: { symbol: symbol }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("ready")
      end
    end

    context "when CDP is online and no fresh data" do
      before do
        allow(LeapsOptionChainSnapshot)
          .to receive_message_chain(:for_symbol, :fresh, :exists?)
          .and_return(false)
        allow_any_instance_of(LeapsRecommendationsController)
          .to receive(:cdp_online?).and_return(true)
        allow(ScrapeLeapsJob).to receive(:perform_later)
      end

      it "enqueues ScrapeLeapsJob and returns a job_id" do
        post "/leaps/analyze", params: { symbol: symbol }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["job_id"]).to be_present
        expect(ScrapeLeapsJob).to have_received(:perform_later)
      end
    end
  end



  # ── 8. fresh data 存在但 candidates 為空時的 fallback 邏輯 ─────────────────
  #
  # 情境：analyze 回傳 "ready"（fresh data 存在），JS 導回 /leaps?symbol=X（無 job_status）。
  # 若 candidates 為空，controller 從 cache 判斷上次狀態，不應顯示空白頁。

  describe "fresh data + empty candidates + partial_error in cache (path B fallback)" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).and_return(
        instance_double(LeapsRankingService, call: [])
      )
      allow(LeapsRecommendationService).to receive(:new).and_return(
        instance_double(LeapsRecommendationService, call: nil)
      )
      allow(LeapsOptionsFlowPanelService).to receive(:new).and_return(
        instance_double(LeapsOptionsFlowPanelService, call: { status: :no_data })
      )
      allow(Rails.cache).to receive(:read)
        .with("leaps_last_errors_#{symbol}")
        .and_return(["Session 在抓取 Strike 255 的 Options Prices 時過期，已抓到的部分資料可能不完整，請重新登入 Barchart 後點查詢重試"])
    end

    it "shows partial_error banner with Barchart login hint, not blank page" do
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Session 在抓取 Strike 255")
      expect(response.body).to include("請重新登入 Barchart 後點查詢重試")
      expect(response.body).not_to include("LEAPS 候選排行")
    end
  end

  describe "fresh data + empty candidates + no cached errors (path B fallback)" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).and_return(
        instance_double(LeapsRankingService, call: [])
      )
      allow(LeapsRecommendationService).to receive(:new).and_return(
        instance_double(LeapsRecommendationService, call: nil)
      )
      allow(LeapsOptionsFlowPanelService).to receive(:new).and_return(
        instance_double(LeapsOptionsFlowPanelService, call: { status: :no_data })
      )
      # no cache stub → cached_errors returns []
    end

    it "shows no_candidates banner, not blank page" do
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("沒有符合篩選條件的候選")
      expect(response.body).to include("Delta 範圍")
      expect(response.body).not_to include("LEAPS 候選排行")
    end
  end

end