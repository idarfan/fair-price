require "rails_helper"

RSpec.describe LeapsRankingService do
  include ActiveSupport::Testing::TimeHelpers

  # All rows in a test share the same scraped_at so maximum() returns all of them.
  around { |ex| freeze_time { ex.run } }

  def make(attrs)
    create(:leaps_option_chain_snapshot, attrs)
  end

  # ── Delta filter ─────────────────────────────────────────────────────────────

  describe "delta filter" do
    before do
      make(delta: 0.74)   # just below min — excluded
      make(delta: 0.75)   # boundary — included
      make(delta: 0.82)   # mid-range — included
      make(delta: 0.90)   # boundary — included
      make(delta: 0.91)   # just above max — excluded
    end

    it "includes only rows with delta in [0.75, 0.90]" do
      results = described_class.new("NOK").call
      deltas  = results.map { |e| e[:delta].to_f }
      expect(deltas).to all(be_between(0.75, 0.90))
      expect(results.size).to eq(3)
    end
  end

  # ── Liquidity tiers ──────────────────────────────────────────────────────────

  describe "liquidity_tiers" do
    before do
      make(delta: 0.80, open_interest: 90_000)
      make(delta: 0.80, open_interest: 50_000)
      make(delta: 0.80, open_interest: 10_000)
    end

    it "assigns 充足 to the top-OI third" do
      result = described_class.new("NOK").call.find { |e| e[:open_interest] == 90_000 }
      expect(result[:liquidity_tier]).to eq("充足")
    end

    it "assigns 普通 to the middle third" do
      result = described_class.new("NOK").call.find { |e| e[:open_interest] == 50_000 }
      expect(result[:liquidity_tier]).to eq("普通")
    end

    it "assigns 偏低 to the bottom third" do
      result = described_class.new("NOK").call.find { |e| e[:open_interest] == 10_000 }
      expect(result[:liquidity_tier]).to eq("偏低")
    end
  end

  # ── vol_oi_ratio warning ──────────────────────────────────────────────────────

  describe "no_recent_volume_warning" do
    before do
      # Three candidates; lowest vol_oi_ratio falls in bottom third → warning
      make(delta: 0.80, open_interest: 90_000, vol_oi_ratio: 0.040)
      make(delta: 0.80, open_interest: 50_000, vol_oi_ratio: 0.020)
      make(delta: 0.80, open_interest: 10_000, vol_oi_ratio: 0.002)
    end

    it "flags the candidate with the lowest vol_oi_ratio (bottom third)" do
      results  = described_class.new("NOK").call
      flagged  = results.select { |e| e[:no_recent_volume_warning] }
      expect(flagged.map { |e| e[:open_interest] }).to contain_exactly(10_000)
    end

    it "does not flag the higher vol_oi_ratio candidates" do
      results   = described_class.new("NOK").call
      unflagged = results.reject { |e| e[:no_recent_volume_warning] }
      expect(unflagged.size).to eq(2)
    end

    context "when vol_oi_ratio is nil" do
      before { make(delta: 0.80, open_interest: 5_000, vol_oi_ratio: nil) }

      it "always flags nil vol_oi_ratio as no_recent_volume_warning" do
        result = described_class.new("NOK").call.find { |e| e[:open_interest] == 5_000 }
        expect(result[:no_recent_volume_warning]).to be true
      end
    end
  end

  # ── Sorting ───────────────────────────────────────────────────────────────────

  describe "sort order" do
    before do
      make(delta: 0.80, open_interest: 30_000, dte: 730)
      make(delta: 0.80, open_interest: 80_000, dte: 180)
      make(delta: 0.80, open_interest: 80_000, dte: 540)
    end

    it "sorts by OI descending, then DTE descending on tie" do
      results = described_class.new("NOK").call
      expect(results.map { |e| [ e[:open_interest], e[:dte] ] }).to eq([
        [ 80_000, 540 ],
        [ 80_000, 180 ],
        [ 30_000, 730 ]
      ])
    end
  end

  # ── time_value_pct ───────────────────────────────────────────────────────────

  describe "time_value_pct" do
    # underlying=13.08, strike=10, mid=(3.1+3.3)/2=3.2
    # intrinsic=3.08, time_value=0.12, time_value_pct=0.12/13.08
    before { make(delta: 0.80, underlying_price: 13.08, strike: 10.0, bid: 3.1, ask: 3.3) }

    it "calculates time_value_pct correctly" do
      result = described_class.new("NOK").call.first
      expect(result[:time_value_pct]).to be_within(0.0001).of(0.12 / 13.08)
    end
  end

  # ── bid_ask_spread_pct ────────────────────────────────────────────────────────

  describe "bid_ask_spread_pct" do
    # mid=3.2, spread=0.2, spread_pct=0.2/3.2=0.0625
    before { make(delta: 0.80, bid: 3.1, ask: 3.3) }

    it "calculates bid_ask_spread_pct correctly" do
      result = described_class.new("NOK").call.first
      expect(result[:bid_ask_spread_pct]).to be_within(0.0001).of(0.2 / 3.2)
    end
  end

  # ── Empty when no candidates ──────────────────────────────────────────────────

  it "returns [] when no rows match the delta filter" do
    make(delta: 0.50)
    expect(described_class.new("NOK").call).to eq([])
  end
end
