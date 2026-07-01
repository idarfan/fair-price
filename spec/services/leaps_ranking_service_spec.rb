require "rails_helper"

RSpec.describe LeapsRankingService do
  include ActiveSupport::Testing::TimeHelpers

  # All rows in one example share the same scraped_at so maximum() returns them all.
  around { |ex| freeze_time { ex.run } }

  def make(attrs)
    create(:leaps_option_chain_snapshot, attrs)
  end

  # ── Delta filter ─────────────────────────────────────────────────────────────

  describe "delta filter" do
    before do
      make(delta: 0.59)   # just below min — excluded
      make(delta: 0.60)   # boundary — included
      make(delta: 0.82)   # mid-range — included
      make(delta: 0.90)   # boundary — included
      make(delta: 0.91)   # just above max — excluded
    end

    it "includes only rows with delta in [0.60, 0.90]" do
      results = described_class.new("NOK").call
      deltas  = results.map { |e| e[:delta].to_f }
      expect(deltas).to all(be_between(0.60, 0.90))
      expect(results.size).to eq(3)
    end
  end

  # ── Liquidity tiers (value-based percentile) ──────────────────────────────────

  describe "liquidity_tiers" do
    context "distinct OI values" do
      before do
        make(delta: 0.80, open_interest: 90_000)
        make(delta: 0.80, open_interest: 50_000)
        make(delta: 0.80, open_interest: 10_000)
      end

      it "assigns 充足 to the top-OI row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 90_000 }
        expect(r[:liquidity_tier]).to eq("充足")
      end

      it "assigns 普通 to the middle row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 50_000 }
        expect(r[:liquidity_tier]).to eq("普通")
      end

      it "assigns 偏低 to the bottom row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 10_000 }
        expect(r[:liquidity_tier]).to eq("偏低")
      end
    end

    context "two rows with identical OI (tie)" do
      before do
        make(delta: 0.80, open_interest: 80_000)
        make(delta: 0.80, open_interest: 80_000)
        make(delta: 0.80, open_interest: 30_000)
      end

      it "gives tied-OI rows the same liquidity tier" do
        results = described_class.new("NOK").call
        tier_80k = results.select { |e| e[:open_interest] == 80_000 }.map { |e| e[:liquidity_tier] }
        expect(tier_80k.uniq.size).to eq(1), "tied OI rows should share a single tier"
      end
    end
  end

  # ── vol_oi_ratio warning ──────────────────────────────────────────────────────

  describe "no_recent_volume_warning" do
    context "with enough candidates (n >= 4)" do
      before do
        make(delta: 0.80, open_interest: 90_000, vol_oi_ratio: 0.040)
        make(delta: 0.80, open_interest: 70_000, vol_oi_ratio: 0.030)
        make(delta: 0.80, open_interest: 50_000, vol_oi_ratio: 0.020)
        make(delta: 0.80, open_interest: 10_000, vol_oi_ratio: 0.002)
      end

      it "flags candidates at or below the 33rd-percentile vol_oi_ratio boundary" do
        results = described_class.new("NOK").call
        flagged = results.select { |e| e[:no_recent_volume_warning] }
        expect(flagged.map { |e| e[:open_interest] }).to contain_exactly(10_000)
      end

      it "does not flag higher vol_oi_ratio candidates" do
        results   = described_class.new("NOK").call
        unflagged = results.reject { |e| e[:no_recent_volume_warning] }
        expect(unflagged.size).to eq(3)
      end
    end

    context "with too few candidates (n < 4) — relative threshold meaningless" do
      before do
        make(delta: 0.80, open_interest: 90_000, vol_oi_ratio: 0.001)  # tiny ratio
        make(delta: 0.80, open_interest: 50_000, vol_oi_ratio: 0.002)
        make(delta: 0.80, open_interest: 10_000, vol_oi_ratio: 0.003)
      end

      it "does not flag any candidate (threshold returns nil)" do
        results = described_class.new("NOK").call
        expect(results.none? { |e| e[:no_recent_volume_warning] }).to be true
      end
    end

    context "when vol_oi_ratio is nil and threshold exists" do
      before do
        make(delta: 0.80, open_interest: 90_000, vol_oi_ratio: 0.040)
        make(delta: 0.80, open_interest: 70_000, vol_oi_ratio: 0.030)
        make(delta: 0.80, open_interest: 50_000, vol_oi_ratio: 0.020)
        make(delta: 0.80, open_interest: 5_000,  vol_oi_ratio: nil)
      end

      it "flags nil vol_oi_ratio when a valid threshold exists" do
        result = described_class.new("NOK").call.find { |e| e[:open_interest] == 5_000 }
        expect(result[:no_recent_volume_warning]).to be true
      end
    end

    context "when vol_oi_ratio is nil and threshold is nil (n < 4)" do
      before do
        make(delta: 0.80, open_interest: 90_000, vol_oi_ratio: nil)
      end

      it "does not flag nil vol_oi_ratio when threshold is also nil" do
        result = described_class.new("NOK").call.first
        expect(result[:no_recent_volume_warning]).to be false
      end
    end
  end

  # ── Sorting ───────────────────────────────────────────────────────────────────

  describe "sort order" do
    before do
      make(delta: 0.80, open_interest: 30_000, dte: 730)
      make(delta: 0.80, open_interest: 80_000, dte: 400)  # was 180 (< 364, now excluded)
      make(delta: 0.80, open_interest: 80_000, dte: 540)
    end

    it "sorts by OI descending, then DTE descending on tie" do
      results = described_class.new("NOK").call
      expect(results.map { |e| [ e[:open_interest], e[:dte] ] }).to eq([
        [ 80_000, 540 ],
        [ 80_000, 400 ],
        [ 30_000, 730 ]
      ])
    end
  end

  # ── time_value_pct ───────────────────────────────────────────────────────────

  describe "time_value_pct" do
    # underlying=13.08, strike=10, mid=3.2
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

  # ── DTE >= 364 hard floor ─────────────────────────────────────────────────────
  #
  # 實測 NOK 時抓到 DTE=5/13/20 的近期合約混進排行（2026-06-28 教訓）。
  # 這組測試確認 DTE<364 的候選真的被排除，DTE>=364 的才進來。

  describe "DTE >= 364 filter" do
    before do
      # Near-term — mirrors the NOK 5/13/20-day garbage data seen in production
      make(delta: 0.82, dte: 5,   expiration_date: Date.today + 5)
      make(delta: 0.82, dte: 13,  expiration_date: Date.today + 13)
      make(delta: 0.82, dte: 20,  expiration_date: Date.today + 20)
      # Boundary: exactly 363 days — still excluded
      make(delta: 0.82, dte: 363, expiration_date: Date.today + 363)
      # Boundary: exactly 364 days — included
      make(delta: 0.82, dte: 364, expiration_date: Date.today + 364)
      # Normal LEAPS DTE — included
      make(delta: 0.82, dte: 400, expiration_date: Date.today + 400)
    end

    it "excludes candidates with DTE < 364" do
      dtes = described_class.new("NOK").call.map { |e| e[:dte] }
      expect(dtes).to all(be >= 364)
    end

    it "includes candidates with DTE >= 364" do
      results = described_class.new("NOK").call
      expect(results.size).to eq(2)   # 364 + 400
    end

    it "explicitly excludes DTE=20 (the NOK near-term case)" do
      results = described_class.new("NOK").call
      expect(results.map { |e| e[:dte] }).not_to include(20)
    end
  end
end
