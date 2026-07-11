# frozen_string_literal: true

require "rails_helper"

RSpec.describe BarchartScraperService, "#fetch_pmcc_short_calls" do
  subject(:service) { described_class.new("NOK") }

  before do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(service).to receive(:log_fetch)
  end

  let(:good_row) do
    {
      "expiration_date" => "2026-07-17", "dte" => 6,
      "strike" => 13.0, "option_type" => "Call",
      "bid" => 0.23, "ask" => 0.25, "mid" => 0.24, "last_price" => 0.23,
      "moneyness" => -0.045, "underlying_price" => 12.44,
      "change" => -0.1, "percent_change" => -0.0085,
      "volume" => 5285, "open_interest" => 26_278, "oi_change" => 3912,
      "vol_oi_ratio" => 0.20, "iv" => 0.7163, "delta" => 0.3339,
      "gamma" => 0.3185, "theta" => -0.0349, "vega" => 0.0058, "rho" => 0.0006,
      "theoretical_price" => 0.24, "itm_probability" => 0.3158
    }
  end

  describe "CDP unavailable" do
    before { allow(service).to receive(:cdp_available?).and_return(false) }

    it "returns status :error without calling run_scraper" do
      expect(service).not_to receive(:run_scraper)
      expect(service.fetch_pmcc_short_calls[:status]).to eq("error")
    end
  end

  describe "success" do
    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ good_row ] } })
    end

    it "returns status :success" do
      expect(service.fetch_pmcc_short_calls[:status]).to eq("success")
    end

    it "persists exactly one row with mid_price = Barchart raw midpoint" do
      service.fetch_pmcc_short_calls
      row = PmccShortCallSnapshot.find_by(symbol: "NOK", strike: 13.0, expiration_date: "2026-07-17")
      expect(row).not_to be_nil
      expect(row.mid_price.to_f).to eq(0.24)
    end

    it "computes intrinsic/extrinsic via LeapsOptionChainSnapshot.derived_values using the stored mid" do
      service.fetch_pmcc_short_calls
      row = PmccShortCallSnapshot.find_by(symbol: "NOK", strike: 13.0, expiration_date: "2026-07-17")
      # strike 13 > underlying 12.44 -> OTM call -> intrinsic 0, extrinsic = mid
      expect(row.intrinsic_value.to_f).to eq(0.0)
      expect(row.extrinsic_value.to_f).to be_within(0.0001).of(0.24)
    end
  end

  describe "mid priority: raw Barchart midpoint wins over (bid+ask)/2" do
    # bid=0.23 ask=0.26 -> (bid+ask)/2=0.245, but Barchart's own midpoint field
    # (mid=0.24) must win — proves persist_pmcc_short_calls doesn't silently
    # recompute from bid/ask when a raw value is already present.
    let(:diverging_mid_row) { good_row.merge("bid" => 0.23, "ask" => 0.26, "mid" => 0.24) }

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ diverging_mid_row ] } })
    end

    it "stores the raw midpoint, not the recomputed (bid+ask)/2" do
      service.fetch_pmcc_short_calls
      row = PmccShortCallSnapshot.find_by(symbol: "NOK", strike: 13.0, expiration_date: "2026-07-17")
      expect(row.mid_price.to_f).to eq(0.24)
      expect(row.mid_price.to_f).not_to be_within(0.0001).of(0.245)
    end
  end

  describe "mid fallback when Barchart midpoint is absent" do
    let(:no_mid_row) { good_row.merge("mid" => nil, "bid" => 0.20, "ask" => 0.30) }

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ no_mid_row ] } })
    end

    it "falls back to (bid+ask)/2" do
      service.fetch_pmcc_short_calls
      row = PmccShortCallSnapshot.find_by(symbol: "NOK", strike: 13.0, expiration_date: "2026-07-17")
      expect(row.mid_price.to_f).to be_within(0.0001).of(0.25)
    end
  end

  describe "mid absent entirely (bid or ask missing)" do
    let(:no_bid_row) { good_row.merge("mid" => nil, "bid" => nil) }

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ no_bid_row ] } })
    end

    it "stores nil mid_price and nil intrinsic/extrinsic (not 0)" do
      service.fetch_pmcc_short_calls
      row = PmccShortCallSnapshot.find_by(symbol: "NOK", strike: 13.0, expiration_date: "2026-07-17")
      expect(row.mid_price).to be_nil
      expect(row.intrinsic_value).to be_nil
      expect(row.extrinsic_value).to be_nil
    end
  end

  describe "barchart_session_expired" do
    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "barchart_session_expired" })
    end

    it "returns status :barchart_session_expired" do
      expect(service.fetch_pmcc_short_calls[:status]).to eq("barchart_session_expired")
    end
  end

  describe "no_candidates" do
    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "no_candidates" })
    end

    it "returns status :no_candidates" do
      expect(service.fetch_pmcc_short_calls[:status]).to eq("no_candidates")
    end
  end

  describe "partial" do
    let(:partial_data) do
      {
        "rows"                  => [ good_row ],
        "expired_at_expiration" => "2026-07-24",
        "expired_layer"         => "volatility_greeks",
        "reason"                => "page_load_timeout",
        "skipped_expirations"   => []
      }
    end

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "partial", data: partial_data })
    end

    it "returns status :partial_error" do
      expect(service.fetch_pmcc_short_calls[:status]).to eq("partial_error")
    end

    it "still persists the rows scraped before the interruption" do
      service.fetch_pmcc_short_calls
      expect(PmccShortCallSnapshot.where(symbol: "NOK").count).to eq(1)
    end

    it "surfaces the expired expiration in errors" do
      errors = service.fetch_pmcc_short_calls[:errors]
      expect(errors).to be_any { |e| e.include?("2026-07-24") }
    end
  end

  describe "error" do
    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "error", error: "No Chrome CDP page found" })
    end

    it "returns status :error with the message" do
      result = service.fetch_pmcc_short_calls
      expect(result[:status]).to eq("error")
      expect(result[:errors]).to include("No Chrome CDP page found")
    end
  end

  describe "persist_pmcc_short_calls scope" do
    let!(:nok_row)  { create(:pmcc_short_call_snapshot, symbol: "NOK") }
    let!(:aapl_row) { create(:pmcc_short_call_snapshot, symbol: "AAPL") }

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ good_row ] } })
    end

    it "deletes the original NOK row and leaves AAPL untouched" do
      service.fetch_pmcc_short_calls
      expect(PmccShortCallSnapshot.exists?(nok_row.id)).to be false
      expect(PmccShortCallSnapshot.exists?(aapl_row.id)).to be true
    end
  end

  describe "incomplete row guard" do
    let(:bad_row) { good_row.merge("strike" => nil) }

    before do
      allow(service).to receive(:run_scraper)
        .with("pmcc_short_call")
        .and_return({ status: "success", data: { "rows" => [ bad_row ] } })
    end

    it "raises a human-readable error instead of inserting incomplete rows" do
      expect { service.fetch_pmcc_short_calls }.to raise_error(/資料不完整/)
    end
  end
end
