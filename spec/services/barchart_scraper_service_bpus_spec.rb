# frozen_string_literal: true

require "rails_helper"

RSpec.describe BarchartScraperService, "#fetch_bpus_expirations and #fetch_bpus_put_chain" do
  subject(:service) { described_class.new("RKLB") }

  # test 環境的 cache_store 是 null_store（config/environments/test.rb），寫入即丟棄
  # ——換成真的 MemoryStore 才能測到 fetch_bpus_* 的快取短路邏輯，測完換回去。
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  before do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(service).to receive(:log_fetch)
  end

  # 真的跑 log_fetch（不 stub），確保 FetchLog::FETCH_TYPES 有登記
  # "bpus_expirations"/"bpus_put_chain"——實測(2026-07-13)發現漏登記時
  # log_fetch 內部的 rescue 會把 RecordInvalid 吞掉、對外完全無症狀，
  # 只留在 log 裡的一行「Fetch type is not included in the list」，
  # 若測試永遠 stub log_fetch 就永遠測不到這個。
  describe "log_fetch is not stubbed: FetchLog inclusion list must include the new fetch_types" do
    before { allow(service).to receive(:log_fetch).and_call_original }

    it "does not raise/log a FetchLog validation error for bpus_expirations" do
      allow(service).to receive(:run_scraper).with("bpus_expirations")
        .and_return({ status: "no_candidates" })
      expect(Rails.logger).not_to receive(:warn).with(/log_fetch failed/)
      service.fetch_bpus_expirations
    end

    it "does not raise/log a FetchLog validation error for bpus_put_chain" do
      allow(service).to receive(:run_scraper).with("bpus_put_chain", extra_args: [ "2026-08-21-m" ])
        .and_return({ status: "no_candidates" })
      expect(Rails.logger).not_to receive(:warn).with(/log_fetch failed/)
      service.fetch_bpus_put_chain(expiration: "2026-08-21-m")
    end
  end

  describe "#fetch_bpus_expirations" do
    describe "CDP unavailable" do
      before { allow(service).to receive(:cdp_available?).and_return(false) }

      it "returns status error without calling run_scraper" do
        expect(service).not_to receive(:run_scraper)
        expect(service.fetch_bpus_expirations[:status]).to eq("error")
      end
    end

    describe "success" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_expirations")
          .and_return({
            status: "success",
            data: { "expirations" => [ "2026-08-21-m", "2026-09-18-m" ], "underlying_price" => 42.5,
                     "debug_url" => "https://www.barchart.com/stocks/quotes/RKLB/options" }
          })
      end

      it "returns status success with expirations and underlying_price" do
        result = service.fetch_bpus_expirations
        expect(result[:status]).to eq("success")
        expect(result[:expirations]).to eq([ "2026-08-21-m", "2026-09-18-m" ])
        expect(result[:underlying_price]).to eq(42.5)
      end

      it "caches the result so a second call does not hit run_scraper again" do
        service.fetch_bpus_expirations
        expect(service).not_to receive(:run_scraper)
        service.fetch_bpus_expirations
      end
    end

    describe "barchart_session_expired" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_expirations")
          .and_return({ status: "barchart_session_expired" })
      end

      it "returns status barchart_session_expired" do
        expect(service.fetch_bpus_expirations[:status]).to eq("barchart_session_expired")
      end

      it "does not cache the error result (retry should re-scrape)" do
        service.fetch_bpus_expirations
        expect(service).to receive(:run_scraper).with("bpus_expirations")
          .and_return({ status: "barchart_session_expired" })
        service.fetch_bpus_expirations
      end
    end

    describe "no_candidates" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_expirations")
          .and_return({ status: "no_candidates" })
      end

      it "returns status no_candidates" do
        expect(service.fetch_bpus_expirations[:status]).to eq("no_candidates")
      end
    end

    describe "error" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_expirations")
          .and_return({ status: "error", error: "No Chrome CDP page found" })
      end

      it "returns status error with the message" do
        result = service.fetch_bpus_expirations
        expect(result[:status]).to eq("error")
        expect(result[:errors]).to include("No Chrome CDP page found")
      end
    end
  end

  describe "#fetch_bpus_put_chain" do
    let(:expiration) { "2026-08-21-m" }

    let(:rows) do
      [
        { "strike" => 40.0, "bid" => 1.10, "ask" => 1.30, "last" => 1.20, "volume" => 120,
          "open_interest" => 500, "iv" => 0.55, "delta" => -0.30, "expiration_date" => "2026-08-21" },
        { "strike" => 35.0, "bid" => nil, "ask" => nil, "last" => nil, "volume" => 0,
          "open_interest" => 0, "iv" => nil, "delta" => nil, "expiration_date" => "2026-08-21" }
      ]
    end

    describe "CDP unavailable" do
      before { allow(service).to receive(:cdp_available?).and_return(false) }

      it "returns status error without calling run_scraper" do
        expect(service).not_to receive(:run_scraper)
        expect(service.fetch_bpus_put_chain(expiration: expiration)[:status]).to eq("error")
      end
    end

    describe "success" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_put_chain", extra_args: [ expiration ])
          .and_return({
            status: "success",
            data: { "rows" => rows, "underlying_price" => 42.5,
                     "debug_url" => "https://www.barchart.com/stocks/quotes/RKLB/options?expiration=#{expiration}&moneyness=100" }
          })
      end

      it "filters out rows where bid and ask are both nil" do
        result = service.fetch_bpus_put_chain(expiration: expiration)
        expect(result[:status]).to eq("success")
        expect(result[:rows].length).to eq(1)
        expect(result[:rows].first["strike"]).to eq(40.0)
      end

      it "caches per (symbol, expiration) so a second call for the same expiration does not re-scrape" do
        service.fetch_bpus_put_chain(expiration: expiration)
        expect(service).not_to receive(:run_scraper)
        service.fetch_bpus_put_chain(expiration: expiration)
      end

      it "does not reuse the cache for a different expiration" do
        service.fetch_bpus_put_chain(expiration: expiration)
        expect(service).to receive(:run_scraper).with("bpus_put_chain", extra_args: [ "2026-09-18-m" ])
          .and_return({ status: "no_candidates" })
        service.fetch_bpus_put_chain(expiration: "2026-09-18-m")
      end
    end

    describe "barchart_session_expired" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_put_chain", extra_args: [ expiration ])
          .and_return({ status: "barchart_session_expired" })
      end

      it "returns status barchart_session_expired" do
        expect(service.fetch_bpus_put_chain(expiration: expiration)[:status]).to eq("barchart_session_expired")
      end
    end

    describe "no_candidates" do
      before do
        allow(service).to receive(:run_scraper)
          .with("bpus_put_chain", extra_args: [ expiration ])
          .and_return({ status: "no_candidates" })
      end

      it "returns status no_candidates" do
        expect(service.fetch_bpus_put_chain(expiration: expiration)[:status]).to eq("no_candidates")
      end
    end
  end
end
