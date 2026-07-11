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

  # ── PMCC v3 §8: pmcc_ranking_for wiring ──────────────────────────────────

  describe "with fresh LEAPS data but no PMCC Short Call data" do
    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(LeapsRankingService, call: fake_candidates))
      allow(LeapsOptionsFlowPanelService).to receive(:new).with(symbol, fake_candidates)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: fake_flow_panel))
      allow(PmccShortCallSnapshot).to receive_message_chain(:for_symbol, :exists?).and_return(false)
    end

    it "returns 200 without invoking PmccRankingService" do
      expect(PmccRankingService).not_to receive(:new)
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with fresh LEAPS data and PMCC Short Call data present" do
    let(:fake_pmcc_ranking) do
      { status: :ok, summary: { total_combos: 0, passing_combos: 0, expirations: [] } }
    end

    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(LeapsRankingService, call: fake_candidates))
      allow(LeapsOptionsFlowPanelService).to receive(:new).with(symbol, fake_candidates)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: fake_flow_panel))
      allow(PmccShortCallSnapshot).to receive_message_chain(:for_symbol, :exists?).and_return(true)
    end

    it "calls PmccRankingService with the symbol" do
      expect(PmccRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(PmccRankingService, call: fake_pmcc_ranking))
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PMCC combo table renders a mutually-exclusive sort toggle row (not per-column headers)" do
    let(:fake_combo) do
      {
        long_leg:  { strike: 7.0, mid: 6.25, bid: 6.2, ask: 6.3, delta: 0.852, dte: 524,
                     oi: 1305, expiration_date: Date.new(2027, 12, 17), intrinsic: 5.44, extrinsic: 0.81 },
        short_leg: { strike: 13.0, mid: 0.24, bid: 0.23, ask: 0.25, theoretical_price: 0.24,
                     moneyness: -0.045, delta: 0.33, gamma: 0.05, theta: -0.02, vega: 0.006,
                     iv: 0.72, itm_probability: 0.32, vol: 100, oi: 500, vol_oi_ratio: 0.2,
                     oi_change: 20, expiration_date: Date.new(2026, 7, 17), dte: 6 },
        spread: 6.0, net_debit: 6.01, max_profit_no_sc: -0.25, max_profit: -0.01,
        premium_yield: 4.0, premium_yield_ann: 243.3,
        passes_golden_rule: false, fail_reason: "PL(6.25) >= Spread(6.00)",
        leaps_delta_ok: true, short_delta_ok: true
      }
    end
    let(:fake_pmcc_ranking) do
      {
        status: :ok,
        "2026-07-17" => {
          expiration: "2026-07-17", expiration_date: Date.new(2026, 7, 17),
          short_dte: 6, combos: [ fake_combo ], has_passing: false
        },
        summary: { total_combos: 1, passing_combos: 0, expirations: [ "2026-07-17" ] }
      }
    end

    before do
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(true)
      allow(LeapsRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(LeapsRankingService, call: fake_candidates))
      allow(LeapsOptionsFlowPanelService).to receive(:new).with(symbol, fake_candidates)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: fake_flow_panel))
      allow(PmccShortCallSnapshot).to receive_message_chain(:for_symbol, :exists?).and_return(true)
      allow(PmccRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(PmccRankingService, call: fake_pmcc_ranking))
    end

    it "renders one toggle per PMCC column, scoped with the table under data-sort-scope" do
      get "/leaps", params: { symbol: symbol }
      body = response.body

      expect(body).to match(/data-sort-scope="true"/)
      expect(body).to match(/data-sort-key="ks"[^>]*class="sort-toggle/)
      expect(body).to match(/data-sort-key="max_profit"[^>]*class="sort-toggle/)
      # LEAPS 排行表本身沒有排序功能（只有 PMCC 表才有），確認沒有意外外溢
      expect(body).not_to match(/id="leaps-th-oi"[^>]*data-sort-key/)
    end

    it "renders each combo row's data-sort-json for the toggle JS to read" do
      get "/leaps", params: { symbol: symbol }
      expect(response.body).to match(/<table[^>]*data-sortable="true"/)
      expect(response.body).to match(/data-sort-json="[^"]*&quot;ks&quot;/)
    end

    it "renders pmcc_ prefixed data-tip-key on every PMCC header (driver.js hover/click explain)" do
      get "/leaps", params: { symbol: symbol }
      body = response.body
      expect(body).to match(/<th data-tip-key="pmcc_ks"/)
      expect(body).to match(/<th data-tip-key="pmcc_max_profit"/)
      expect(body).to match(/<th data-tip-key="pmcc_passes"/)
      # 這個 fixture 只有 1 個到期日桶；真實資料有 3 桶時，同一個 key 的 th
      # 會出現 3 次（沒有唯一 id，故意設計成這樣，見 render_pmcc_table 註解）。
      expect(body.scan('data-tip-key="pmcc_ks"').size).to eq(1)
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
        .and_return([ "抓取時發生系統錯誤" ])
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
        .and_return([ "Session 在抓取 Strike 255 的 Options Prices 時過期，已抓到的部分資料可能不完整，請重新登入 Barchart 後點查詢重試" ])
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


  # ── 9. invalid_strike — snapshot 驗證三條路徑 ─────────────────────────────────
  describe "POST /leaps/analyze — snapshot validation" do
    let(:symbol) { "KLAC" }

    before do
      # Stub fresh-data check: no fresh data → would proceed to CDP check
      allow(LeapsOptionChainSnapshot)
        .to receive_message_chain(:for_symbol, :fresh, :exists?)
        .and_return(false)
      allow_any_instance_of(LeapsRecommendationsController)
        .to receive(:cdp_online?).and_return(true)
      allow(ScrapeLeapsJob).to receive(:perform_later)
    end

    context "snapshot exists + user_strike out of range" do
      before do
        StrikeChainSnapshot.upsert(
          { symbol: symbol, strikes: [ 500.0, 520.0, 540.0 ], spot_price: 510.0, scraped_at: Time.current },
          unique_by: :symbol
        )
      end

      after { StrikeChainSnapshot.where(symbol: symbol).delete_all }

      it "returns invalid_strike without enqueueing a job" do
        expect(ScrapeLeapsJob).not_to receive(:perform_later)
        post "/leaps/analyze", params: { symbol: symbol, user_strike: "7" },
                               as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("invalid_strike")
        expect(body["message"]).to include("7")
        expect(body["message"]).to include("500")
      end
    end

    context "snapshot exists + user_strike in range" do
      before do
        StrikeChainSnapshot.upsert(
          { symbol: symbol, strikes: [ 500.0, 520.0, 540.0 ], spot_price: 510.0, scraped_at: Time.current },
          unique_by: :symbol
        )
      end

      after { StrikeChainSnapshot.where(symbol: symbol).delete_all }

      it "enqueues job (strike valid)" do
        post "/leaps/analyze", params: { symbol: symbol, user_strike: "520" },
                               as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).not_to eq("invalid_strike")
        expect(ScrapeLeapsJob).to have_received(:perform_later)
      end
    end

    context "no snapshot for symbol" do
      before { StrikeChainSnapshot.where(symbol: symbol).delete_all }

      it "enqueues job even if user_strike seems wrong (no snapshot to validate against)" do
        post "/leaps/analyze", params: { symbol: symbol, user_strike: "7" },
                               as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).not_to eq("invalid_strike")
        expect(ScrapeLeapsJob).to have_received(:perform_later)
      end
    end
  end

  # ── 9. fresh window 邊界（真實 DB rows，不 stub fresh scope）────────────────
  # spec「fresh window 5 → 30 分鐘」節要求的 travel_to 邊界測試：
  # 窗內 → cache hit 不排 job；窗外 → cache miss 排 job。
  # 邊界用 FRESH_WINDOW ± 1.minute 表達，不寫死分鐘數。
  describe "POST /leaps/analyze — fresh window boundary (real DB)" do
    let(:symbol) { "FWREQ" }
    let(:base_attrs) do
      {
        symbol: symbol, expiration_date: Date.new(2028, 1, 21),
        strike: 10.0, option_type: "Call"
      }
    end

    before do
      allow_any_instance_of(LeapsRecommendationsController)
        .to receive(:cdp_online?).and_return(true)
      allow(ScrapeLeapsJob).to receive(:perform_later)
    end

    after { LeapsOptionChainSnapshot.where(symbol: symbol).delete_all }

    context "snapshot scraped just inside FRESH_WINDOW" do
      it "returns ready and does NOT enqueue a job (cache hit)" do
        travel_to Time.current do
          LeapsOptionChainSnapshot.create!(
            base_attrs.merge(scraped_at: (LeapsOptionChainSnapshot::FRESH_WINDOW - 1.minute).ago)
          )
          post "/leaps/analyze", params: { symbol: symbol }
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)["status"]).to eq("ready")
          expect(ScrapeLeapsJob).not_to have_received(:perform_later)
        end
      end
    end

    context "snapshot scraped just outside FRESH_WINDOW" do
      it "enqueues a job (cache miss)" do
        travel_to Time.current do
          LeapsOptionChainSnapshot.create!(
            base_attrs.merge(scraped_at: (LeapsOptionChainSnapshot::FRESH_WINDOW + 1.minute).ago)
          )
          post "/leaps/analyze", params: { symbol: symbol }
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)["job_id"]).to be_present
          expect(ScrapeLeapsJob).to have_received(:perform_later)
        end
      end
    end
  end

  # ── 9b. fresh 快取必須「中心履約價吻合」才算數，不能只看時間窗 ─────────────
  # 根因（2026-07-09 NOK 履約價 7 查出跟輸入無關的候選；同日再追一個對稱案例：
  # 留空查詢卻沿用了上一次手動指定履約價留下的窄範圍候選）：上一次查詢（自動
  # 偵測或別的履約價）留下的候選在 FRESH_WINDOW 內，這次換一種查詢方式
  # （不同履約價、或手動→留空、或留空→手動）時，舊版 fresh_data_exists? 只看
  # 時間新舊，於是誤判為 cache hit，沿用跟這次請求無關的舊候選。
  # 判斷依據唯一權威：LeapsOptionChainSnapshot.fresh_for?（比對
  # StrikeChainSnapshot#last_query_strike 是否等於這次的 user_strike，nil 也要
  # 精準比對，代表「上次是不是也留空查詢」）。
  describe "POST /leaps/analyze — fresh cache must match the requested query center" do
    let(:symbol) { "COVREQ" }

    before do
      allow_any_instance_of(LeapsRecommendationsController)
        .to receive(:cdp_online?).and_return(true)
      allow(ScrapeLeapsJob).to receive(:perform_later)
    end

    after do
      LeapsOptionChainSnapshot.where(symbol: symbol).delete_all
      StrikeChainSnapshot.where(symbol: symbol).delete_all
    end

    # 履約價階梯故意涵蓋 7 跟 12，避免 seed 出的資料被 analyze 快速路徑的
    # StrikeChainSnapshot#valid_strike? 誤判成 invalid_strike——這裡要測的是
    # fresh_for? 的中心點比對，不是履約價合法性檢查。
    def seed_snapshot(symbol, strike:, last_query_strike:)
      LeapsOptionChainSnapshot.create!(
        symbol: symbol, expiration_date: Date.new(2028, 1, 21),
        strike: strike, option_type: "Call", scraped_at: Time.current
      )
      StrikeChainSnapshot.upsert(
        { symbol: symbol, strikes: [ 7.0, 12.0 ], spot_price: strike,
          last_query_strike: last_query_strike, scraped_at: Time.current },
        unique_by: :symbol
      )
    end

    context "fresh candidates centered on a different strike than the new request" do
      it "treats it as cache miss and enqueues a re-scrape centered on the new strike" do
        seed_snapshot(symbol, strike: 12.0, last_query_strike: 12.0)
        post "/leaps/analyze", params: { symbol: symbol, user_strike: "7" }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).not_to eq("invalid_strike")
        expect(body["job_id"]).to be_present
        expect(ScrapeLeapsJob).to have_received(:perform_later).with(symbol, anything, user_strike: 7.0)
      end
    end

    context "fresh candidates already centered on exactly the requested strike" do
      it "returns ready and does NOT enqueue a job" do
        seed_snapshot(symbol, strike: 7.0, last_query_strike: 7.0)
        post "/leaps/analyze", params: { symbol: symbol, user_strike: "7" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("ready")
        expect(ScrapeLeapsJob).not_to have_received(:perform_later)
      end
    end

    context "last query was a manual strike, this request leaves it blank (auto mode)" do
      it "treats it as cache miss and re-scrapes in auto mode (not just the narrow manual strike range)" do
        seed_snapshot(symbol, strike: 7.0, last_query_strike: 7.0)
        post "/leaps/analyze", params: { symbol: symbol }, as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["job_id"]).to be_present
        expect(ScrapeLeapsJob).to have_received(:perform_later).with(symbol, anything, user_strike: nil)
      end
    end

    context "last query was auto mode, this request is also blank" do
      it "returns ready and does NOT enqueue a job" do
        seed_snapshot(symbol, strike: 12.0, last_query_strike: nil)
        post "/leaps/analyze", params: { symbol: symbol }, as: :json
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("ready")
        expect(ScrapeLeapsJob).not_to have_received(:perform_later)
      end
    end
  end
  # ── 10. Phase H：內在/外在價值欄位走完整 HTTP 路徑（真實 DB rows）──────────────
  # 規格明文：「兩個 service 單元測試全過、controller 串接處從未被 request 過、
  # 使用者一按就炸」的前例，request spec 必交付。
  describe "GET /leaps — Phase H derived columns (real DB)" do
    let(:symbol) { "PHREQ" }

    before do
      create(:leaps_option_chain_snapshot,
             symbol: symbol, dte: 400, delta: 0.80,
             strike: 10.0, bid: 3.1, ask: 3.3, underlying_price: 13.08,
             scraped_at: Time.current)
    end

    after { LeapsOptionChainSnapshot.where(symbol: symbol).delete_all }

    it "renders the three new columns with correct values" do
      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include("內在價值")
      expect(body).to include("外在價值")
      expect(body).to include("外在佔比")

      # factory 依唯一公式補值：mid 3.2、內在 3.08、外在 0.12、佔比 0.12/3.2 = 3.8%
      expect(body).to include("3.08")
      expect(body).to include("0.12")
      expect(body).to include("3.8%")
    end

    it "renders — for extrinsic_pct when bid/ask missing" do
      LeapsOptionChainSnapshot.where(symbol: symbol).delete_all
      create(:leaps_option_chain_snapshot,
             symbol: symbol, dte: 400, delta: 0.80,
             strike: 10.0, bid: nil, ask: nil, underlying_price: 13.08,
             scraped_at: Time.current)

      get "/leaps", params: { symbol: symbol }
      expect(response).to have_http_status(:ok)
      # 內在/外在/佔比三欄皆缺值 → 顯示 —（fmt helpers 的 nil 行為）
      expect(response.body).to include("—")
      expect(response.body).not_to include("NaN")
    end
  end
end
