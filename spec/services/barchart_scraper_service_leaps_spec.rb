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

  # ── 3b. V&G-only session expiry ─────────────────────────────────────────────
  #
  # Options Prices fetched cleanly; V&G session expires on a later expiration.
  # The Ruby service must propagate partial_error AND name "Volatility & Greeks"
  # in the error — NOT "Options Prices" — so the caller can tell the two apart.
  #
  # Root cause confirmed: when Barchart session expires on the V&G page, the page
  # does NOT navigate away — bc-data-grid._data returns [] (empty array), not null.
  # JavaScript: ![] === false, so the guard (if !grid._data) never fires → returns []
  # Python: [] is None → False → the old "if vg_rows is None" check never triggered
  # → _merge_vg(opts_rows, []) ran silently → null V&G fields → loop continued → success
  #
  # Fix in leaps_scraper.py: "if not vg_rows" catches both None and [].
  # This Ruby test mocks at the run_scraper level (tests Ruby service behaviour);
  # the Python-level [] vs None distinction is covered by the scraper fix above.

  describe "V&G-only session expiry (Options Prices fetched cleanly)" do
    let(:vg_partial_rows) do
      [{
        "expiration_date" => "2027-01-15", "dte" => 365,
        "strike" => 10.0, "option_type" => "Call",
        "bid" => 3.1, "ask" => 3.3, "last_price" => 3.2,
        "underlying_price" => 13.08,
        "volume" => 100, "open_interest" => 41_000,
        "delta" => 0.82, "iv" => 0.74,
        "itm_probability" => nil, "vol_oi_ratio" => nil, "vega" => nil
      }]
    end

    let(:vg_partial_data) do
      {
        "status"                => "partial",
        "rows"                  => vg_partial_rows,
        "expired_at_expiration" => "2027-06-20",
        "expired_layer"         => "volatility_greeks"
      }
    end

    before do
      stub_cache(hit: false)
      allow(service).to receive(:run_scraper)
        .and_return({ status: "partial", data: vg_partial_data })
      allow(service).to receive(:persist_leaps).and_call_original
      allow(LeapsOptionChainSnapshot).to receive_message_chain(:where, :delete_all)
      allow(LeapsOptionChainSnapshot).to receive(:insert_all)
    end

    it "returns :partial_error, not :success" do
      expect(service.fetch_leaps[:status]).to eq("partial_error")
    end

    it "names Volatility and Greeks in the error, not Options Prices" do
      errors = service.fetch_leaps[:errors]
      expect(errors.first).to include("Volatility & Greeks")
      expect(errors.first).not_to include("Options Prices")
    end

    it "includes the expired expiration date in the error" do
      errors = service.fetch_leaps[:errors]
      expect(errors.first).to include("2027-06-20")
    end

    it "still persists the already-scraped rows including this expiration with nil V&G fields" do
      expect(service).to receive(:persist_leaps).with(vg_partial_data)
      service.fetch_leaps
    end
  end

  # ── 4. Consecutive scrapes: second scrape replaces first entirely ─────────────
  #
  # persist_leaps runs delete_all + insert_all in one transaction, so only one
  # batch (one scraped_at) should ever exist per symbol.  This test verifies
  # that after two successive scrapes the old batch is fully gone.

  describe "consecutive scrapes replace old batch" do
    include ActiveSupport::Testing::TimeHelpers

    let(:batch_row) do
      ->(strike, scraped_at) do
        {
          "expiration_date" => "2027-01-15", "dte" => 202,
          "strike" => strike, "option_type" => "Call",
          "bid" => 3.1, "ask" => 3.3, "last_price" => 3.2,
          "underlying_price" => 13.08, "volume" => 100, "open_interest" => 500,
          "delta" => 0.78, "iv" => 0.76,
          "itm_probability" => 0.82, "vol_oi_ratio" => 0.006, "vega" => 0.013
        }
      end
    end

    it "leaves only the most recent scrape's rows in the DB" do
      # First scrape at T=0: one row with strike 10
      travel_to(1.hour.ago) do
        service.send(:persist_leaps, { "rows" => [ batch_row.call(10.0, Time.current) ] })
      end

      first_scraped_at = LeapsOptionChainSnapshot.where(symbol: "NOK").maximum(:scraped_at)
      expect(LeapsOptionChainSnapshot.where(symbol: "NOK").count).to eq(1)

      # Second scrape at T=1: one row with strike 12 (different strike → no uniqueness conflict)
      travel_to(Time.current) do
        service.send(:persist_leaps, { "rows" => [ batch_row.call(12.0, Time.current) ] })
      end

      second_scraped_at = LeapsOptionChainSnapshot.where(symbol: "NOK").maximum(:scraped_at)

      # The second batch's scraped_at must be later than the first
      expect(second_scraped_at).to be > first_scraped_at

      # Only one row should remain — the second batch's row
      expect(LeapsOptionChainSnapshot.where(symbol: "NOK").count).to eq(1)
      expect(LeapsOptionChainSnapshot.where(symbol: "NOK").pluck(:strike).map(&:to_f)).to eq([12.0])

      # No rows with the old scraped_at should exist
      expect(LeapsOptionChainSnapshot.where(symbol: "NOK", scraped_at: first_scraped_at)).not_to exist
    end
  end

  # ── 5. Phase G: user_strike parameter ─────────────────────────────────────
  # Tests verify that:
  #   a) user_strike is passed to run_scraper as CLI arg
  #   b) no_candidates status is surfaced when Python returns it
  #   c) expired_at_strike (new stacked partial) is surfaced correctly
  #   d) Stage 1 auto-detection (no user_strike) still works

  describe "fetch_leaps with user_strike" do
    let(:scraper_success) do
      {
        "status" => "success",
        "rows"   => [
          {
            "expiration_date" => "2027-01-15", "dte" => 202,
            "strike" => 10.0, "option_type" => "Call",
            "bid" => 3.5, "ask" => 3.7, "last_price" => 3.6,
            "underlying_price" => 13.0, "volume" => 200, "open_interest" => 600,
            "delta" => 0.82, "iv" => 0.75, "itm_probability" => 0.85,
            "vol_oi_ratio" => 0.007, "vega" => 0.015
          }
        ]
      }
    end

    before do
      allow(LeapsOptionChainSnapshot).to receive_message_chain(:for_symbol, :fresh, :exists?).and_return(false)
    end

    it "passes user_strike as CLI extra arg when provided" do
      expect(service).to receive(:run_scraper)
        .with("leaps", extra_args: ["10.0"])
        .and_return({ status: "success", data: scraper_success })
      allow(service).to receive(:persist_leaps)

      service.fetch_leaps(user_strike: 10.0)
    end

    it "omits extra_args when user_strike is nil (auto mode)" do
      expect(service).to receive(:run_scraper)
        .with("leaps", extra_args: [])
        .and_return({ status: "success", data: scraper_success })
      allow(service).to receive(:persist_leaps)

      service.fetch_leaps(user_strike: nil)
    end

    it "returns status: no_candidates when Python returns no_candidates" do
      allow(service).to receive(:run_scraper).and_return({ status: "no_candidates" })
      result = service.fetch_leaps(user_strike: nil)
      expect(result[:status]).to eq("no_candidates")
    end

    it "returns no_candidates even when user_strike is specified" do
      allow(service).to receive(:run_scraper).and_return({ status: "no_candidates" })
      result = service.fetch_leaps(user_strike: 10.0)
      expect(result[:status]).to eq("no_candidates")
    end
  end

  # ── 6. Phase G: expired_at_strike partial (stacked strategy) ─────────────
  # The stacked scraper returns expired_at_strike when session expires while
  # iterating over candidate strikes — distinct from expired_at_expiration.

  describe "partial result with expired_at_strike (stacked strategy session expiry)" do
    let(:partial_data) do
      {
        "status"            => "partial",
        "rows"              => [
          {
            "expiration_date" => "2027-01-15", "dte" => 202,
            "strike" => 10.0, "option_type" => "Call",
            "bid" => 3.5, "ask" => 3.7, "last_price" => nil,
            "underlying_price" => 13.0, "volume" => 100, "open_interest" => 400,
            "delta" => 0.82, "iv" => 0.75,
            "itm_probability" => nil, "vol_oi_ratio" => nil, "vega" => nil
          }
        ],
        "expired_at_strike" => 11.0,
        "expired_layer"     => "options_prices"
      }
    end

    before do
      allow(LeapsOptionChainSnapshot).to receive_message_chain(:for_symbol, :fresh, :exists?).and_return(false)
      allow(service).to receive(:run_scraper).and_return({ status: "partial", data: partial_data })
      allow(service).to receive(:persist_leaps)
    end

    it "returns partial_error status" do
      expect(service.fetch_leaps[:status]).to eq("partial_error")
    end

    it "includes Strike reference (not expiration date) in error message" do
      errors = service.fetch_leaps[:errors]
      expect(errors.first).to include("Strike 11.0")
    end

    it "still persists the already-scraped rows" do
      expect(service).to receive(:persist_leaps).with(partial_data)
      service.fetch_leaps
    end
  end

  # ── 7. Stage 1/Stage 2 Delta filter separation ────────────────────────────
  # Delta 0.80 (Stage 1) and Delta 0.75-0.90 (Stage 2) are SEPARATE rules.
  # A row with Delta 0.91 must NOT appear in final output because it fails Stage 2.
  # This is enforced in Ruby (LeapsRankingService), not in the scraper.
  # Test here confirms the scraper itself does NOT drop rows — ranking does.

  describe "scraper does not apply Stage 2 filter (Ruby side handles it)" do
    let(:wide_delta_data) do
      {
        "status" => "success",
        "rows"   => [
          { "expiration_date" => "2027-01-15", "dte" => 202, "strike" => 9.0,
            "option_type" => "Call", "delta" => 0.91, "underlying_price" => 13.0,
            "bid" => nil, "ask" => nil, "last_price" => nil, "volume" => nil,
            "open_interest" => nil, "iv" => nil, "itm_probability" => nil,
            "vol_oi_ratio" => nil, "vega" => nil },
          { "expiration_date" => "2027-01-15", "dte" => 202, "strike" => 10.0,
            "option_type" => "Call", "delta" => 0.82, "underlying_price" => 13.0,
            "bid" => nil, "ask" => nil, "last_price" => nil, "volume" => nil,
            "open_interest" => nil, "iv" => nil, "itm_probability" => nil,
            "vol_oi_ratio" => nil, "vega" => nil }
        ]
      }
    end

    before do
      allow(LeapsOptionChainSnapshot).to receive_message_chain(:for_symbol, :fresh, :exists?).and_return(false)
      allow(service).to receive(:run_scraper).and_return({ status: "success", data: wide_delta_data })
    end

    it "persists ALL rows including Delta 0.91 (Stage 2 filter not applied here)" do
      expect(service).to receive(:persist_leaps) do |data|
        strikes = data["rows"].map { |r| r["delta"] }
        expect(strikes).to include(0.91)
        expect(strikes).to include(0.82)
      end
      service.fetch_leaps
    end
  end

end
