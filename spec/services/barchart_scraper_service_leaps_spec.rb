require "rails_helper"

RSpec.describe BarchartScraperService, "#fetch_leaps" do
  subject(:service) { described_class.new("NOK") }

  before do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(service).to receive(:log_fetch)
  end

  # ── Helper: stub the 5-minute cache check ───────────────────────────────────

  def stub_cache(hit:)
    allow(LeapsOptionChainSnapshot)
      .to receive_message_chain(:for_symbol, :fresh, :exists?)
      .and_return(hit)
  end

  # ── 1. Cache hit: persist_leaps must never be called ────────────────────────

  describe "cache hit" do
    before { stub_cache(hit: true) }

    it "returns status :cached" do
      expect(service.fetch_leaps[:status]).to eq("cached")
    end

    it "does not call persist_leaps at all" do
      # not_to receive is call-count enforcement, not a DB state check
      expect(service).not_to receive(:persist_leaps)
      service.fetch_leaps
    end

    it "does not invoke the Python scraper" do
      expect(service).not_to receive(:run_scraper)
      service.fetch_leaps
    end
  end

  # ── 2. delete_all only touches the queried symbol's rows ────────────────────

  describe "persist_leaps scope" do
    let!(:nok_row)  { create(:leaps_option_chain_snapshot, symbol: "NOK") }
    let!(:aapl_row) { create(:leaps_option_chain_snapshot, symbol: "AAPL") }

    let(:one_row) do
      [{
        "expiration_date" => "2027-01-15", "dte" => 202,
        "strike" => 10.0, "option_type" => "Call",
        "bid" => 3.1, "ask" => 3.3, "last_price" => 3.2,
        "underlying_price" => 13.08,
        "volume" => 100, "open_interest" => 500,
        "delta" => 0.78, "iv" => 0.76,
        "itm_probability" => 0.82, "vol_oi_ratio" => 0.006, "vega" => 0.013
      }]
    end

    it "deletes the original NOK row by id" do
      service.send(:persist_leaps, { "rows" => one_row })
      expect(LeapsOptionChainSnapshot.exists?(nok_row.id)).to be false
    end

    it "leaves AAPL untouched" do
      service.send(:persist_leaps, { "rows" => one_row })
      expect(LeapsOptionChainSnapshot.exists?(aapl_row.id)).to be true
    end

    it "inserts exactly one new NOK row after deleting the old one" do
      service.send(:persist_leaps, { "rows" => one_row })
      expect(LeapsOptionChainSnapshot.where(symbol: "NOK").count).to eq(1)
    end
  end

  # ── 3. Session expiry mid-loop ───────────────────────────────────────────────
  #
  # Decision (Phase B spec): partial status → persist whatever rows already
  # scraped, then surface partial_error to the caller.  The test must verify
  # both the error surface AND that persist_leaps was actually invoked with
  # the partial data (not silently skipped).

  describe "session expiry mid-loop" do
    let(:partial_rows) do
      [{
        "expiration_date" => "2026-06-20", "dte" => 357,
        "strike" => 8.0, "option_type" => "Call",
        "bid" => 5.1, "ask" => 5.3, "last_price" => 5.2,
        "underlying_price" => 13.08,
        "volume" => 200, "open_interest" => 41_000,
        "delta" => 0.85, "iv" => 0.70,
        "itm_probability" => 0.88, "vol_oi_ratio" => 0.005, "vega" => 0.011
      }]
    end

    let(:partial_data) do
      {
        "status"                => "partial",
        "rows"                  => partial_rows,
        "expired_at_expiration" => "2027-01-15"
      }
    end

    before do
      stub_cache(hit: false)
      allow(service).to receive(:run_scraper).and_return({ status: "partial", data: partial_data })
      # Use spy pattern so we can assert it WAS called
      allow(service).to receive(:persist_leaps).and_call_original
      # Prevent actual DB writes (persist_leaps hits the real DB in unit context)
      allow(LeapsOptionChainSnapshot).to receive_message_chain(:where, :delete_all)
      allow(LeapsOptionChainSnapshot).to receive(:insert_all)
    end

    it "returns status :partial_error" do
      expect(service.fetch_leaps[:status]).to eq("partial_error")
    end

    it "includes the expired expiration date in the errors array" do
      errors = service.fetch_leaps[:errors]
      expect(errors).to be_any { |e| e.include?("2027-01-15") }
    end

    it "does not silently return :success" do
      expect(service.fetch_leaps[:status]).not_to eq("success")
    end

    it "still persists the already-scraped rows despite the mid-loop expiry" do
      # persist_leaps must be called with the partial data so rows scraped
      # before expiry are not lost.
      expect(service).to receive(:persist_leaps).with(partial_data)
      service.fetch_leaps
    end
  end
end
