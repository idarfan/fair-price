# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P2：LEAPS 查詢成功後寫 IV 曲面（失敗不得影響 LEAPS 結果），
# 以及 Barchart Options Overview History 的抓取。爬蟲以 run_scraper 層級 stub。
RSpec.describe BarchartScraperService do
  subject(:service) { described_class.new("TSM") }

  before do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(OptionsFlow).to receive_message_chain(:where, :exists?).and_return(true)
    allow(LeapsOptionChainSnapshot).to receive(:fresh_for?).and_return(false)
    # 測試時間不得影響結果：預設非盤中，盤中行為在下方個別測
    allow(LeapsIvCapture).to receive(:regular_session?).and_return(false)
  end

  let(:leaps_row) do
    { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 350.0, "option_type" => "Call",
      "bid" => 96.0, "ask" => 97.5, "last_price" => 96.75, "underlying_price" => 353.1,
      "volume" => 10, "open_interest" => 500, "delta" => 0.6258, "iv" => 0.4246,
      "itm_probability" => 0.6, "vol_oi_ratio" => 0.02, "vega" => 1.23 }
  end
  let(:leaps_data) do
    { "status" => "success", "rows" => [ leaps_row ], "underlying_price" => 353.1,
      "chain_snapshot" => { "strikes" => [ 350.0 ], "spot_price" => 353.1, "expiration" => "2027-12-17" },
      "quote_date_text" => "11/05/26", "source_url" => "https://www.barchart.com/stocks/quotes/TSM/options",
      "iv_surface" => [ { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 350.0, "iv" => 0.4246, "delta" => 0.6258 },
                        { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 420.0, "iv" => 0.41, "delta" => 0.45 } ],
      "iv_surface_error" => nil }
  end

  describe "#fetch_leaps" do
    it "成功時寫入 IV 曲面與快照（source 預設 adhoc），fetch_logs 記一筆 leaps_iv_surface" do
      allow(service).to receive(:run_scraper).with("leaps", extra_args: []).and_return({ status: "success", data: leaps_data })

      expect(service.fetch_leaps[:status]).to eq("success")
      expect(LeapsIvSurfacePoint.where(symbol: "TSM").pluck(:strike).map(&:to_f).sort).to eq([ 350.0, 420.0 ])
      expect(LeapsIvSnapshot.find_by(symbol: "TSM")).to have_attributes(as_of_date: Date.new(2026, 11, 5), source: "adhoc")
      expect(FetchLog.where(symbol: "TSM", fetch_type: "leaps_iv_surface").pluck(:status, :error_detail))
        .to eq([ [ "success", "points=2" ] ])
    end

    it "iv_source: scheduled 時快照記 scheduled（P4 排程用）" do
      allow(service).to receive(:run_scraper).and_return({ status: "success", data: leaps_data })

      service.fetch_leaps(iv_source: "scheduled")
      expect(LeapsIvSnapshot.find_by(symbol: "TSM").source).to eq("scheduled")
    end

    it "非盤中不帶 --skip-iv-surface" do
      expect(service).to receive(:run_scraper).with("leaps", extra_args: [ "350.0" ])
        .and_return({ status: "success", data: leaps_data })

      service.fetch_leaps(user_strike: 350.0)
    end

    it "美股盤中：爬蟲帶 --skip-iv-surface（Stage 3 不跑），不寫 IV 曲面與快照、不記 fetch_logs；LEAPS 照常" do
      allow(LeapsIvCapture).to receive(:regular_session?).and_return(true)
      expect(service).to receive(:run_scraper).with("leaps", extra_args: [ "350.0", "--skip-iv-surface" ])
        .and_return({ status: "success", data: leaps_data })

      expect(service.fetch_leaps(user_strike: 350.0)[:status]).to eq("success")
      expect(LeapsOptionChainSnapshot.where(symbol: "TSM").count).to eq(1)
      expect(LeapsIvSnapshot.count + LeapsIvSurfacePoint.count).to eq(0)
      expect(FetchLog.where(fetch_type: "leaps_iv_surface")).to be_empty
    end

    it "盤中與否只在開始時判斷一次：查詢中途收盤也不會改成寫入" do
      allow(LeapsIvCapture).to receive(:regular_session?).and_return(true, false)
      allow(service).to receive(:run_scraper).and_return({ status: "success", data: leaps_data.merge("iv_surface" => []) })

      service.fetch_leaps
      expect(LeapsIvCapture).to have_received(:regular_session?).once
      expect(FetchLog.where(fetch_type: "leaps_iv_surface")).to be_empty
    end

    it "曲面寫入失敗：LEAPS 照樣成功、候選列照樣寫入，fetch_logs 記 error" do
      broken = leaps_data.merge("quote_date_text" => nil)
      allow(service).to receive(:run_scraper).and_return({ status: "success", data: broken })

      expect(service.fetch_leaps[:status]).to eq("success")
      expect(LeapsOptionChainSnapshot.where(symbol: "TSM").count).to eq(1)
      expect(LeapsIvSnapshot.count + LeapsIvSurfacePoint.count).to eq(0)
      expect(FetchLog.find_by(symbol: "TSM", fetch_type: "leaps_iv_surface"))
        .to have_attributes(status: "error", error_detail: a_string_including("報價日期"))
    end
  end

  describe "#fetch_barchart_iv_history" do
    let(:history_data) do
      { "status" => "success", "mode" => "backfill", "quote_date_text" => "11/05/26", "hv_pct" => 46.66,
        "source_url" => "https://www.barchart.com/stocks/quotes/TSM/options-history",
        "hv_source_url" => "https://www.barchart.com/stocks/quotes/TSM/overview",
        "rows" => [ { "date" => "2026-11-05", "weightedImpliedVolatility" => 0.5192, "impliedVolatilityRank1y" => 82.44,
                      "impliedVolatilityPercentile1y" => 0.9243, "putCallVolumeRatio" => 0.92, "totalVolume" => 1,
                      "putCallOpenInterestRatio" => 0.98, "totalOpenInterest" => 2, "historicalLastPrice" => 353.1 } ] }
    end

    it "把 mode 傳給爬蟲，成功時寫入並記 fetch_logs" do
      expect(service).to receive(:run_scraper).with("barchart_iv_history", extra_args: [ "backfill" ])
        .and_return({ status: "success", data: history_data })

      expect(service.fetch_barchart_iv_history(mode: "backfill")[:status]).to eq("success")
      expect(BarchartIvHistory.find_by(symbol: "TSM").iv_pctl).to eq(BigDecimal("92.43"))
      expect(FetchLog.find_by(symbol: "TSM", fetch_type: "barchart_iv_history"))
        .to have_attributes(status: "success", error_detail: "mode=backfill rows=1")
    end

    it "寫入驗證失敗時回 error 並記錄，不往外拋" do
      allow(service).to receive(:run_scraper).and_return({ status: "success", data: history_data.merge("hv_pct" => nil) })

      result = service.fetch_barchart_iv_history(mode: "latest")
      expect(result[:status]).to eq("error")
      expect(FetchLog.find_by(fetch_type: "barchart_iv_history").status).to eq("error")
    end

    it "Session 過期如實回報" do
      allow(service).to receive(:run_scraper).and_return({ status: "barchart_session_expired" })

      expect(service.fetch_barchart_iv_history(mode: "latest")[:status]).to eq("barchart_session_expired")
      expect(FetchLog.find_by(fetch_type: "barchart_iv_history").status).to eq("barchart_session_expired")
    end

    it "美股盤中不跑爬蟲、不寫入" do
      allow(LeapsIvCapture).to receive(:regular_session?).and_return(true)
      expect(service).not_to receive(:run_scraper)

      expect(service.fetch_barchart_iv_history(mode: "latest")[:status]).to eq("skipped_regular_session")
      expect(BarchartIvHistory.count).to eq(0)
    end

    it "CDP 不在線時不跑爬蟲" do
      allow(service).to receive(:cdp_available?).and_return(false)
      expect(service).not_to receive(:run_scraper)

      expect(service.fetch_barchart_iv_history(mode: "latest")[:status]).to eq("error")
    end
  end
end
