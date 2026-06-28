require "rails_helper"

RSpec.describe LeapsOptionsFlowPanelService do
  include ActiveSupport::Testing::TimeHelpers

  around { |ex| freeze_time { ex.run } }

  let(:symbol) { "NOK" }

  def make_flow(attrs = {})
    create(:options_flow_trade, { symbol: symbol, snapshot_date: Date.current }.merge(attrs))
  end

  def candidate(strike:, expiry:)
    { strike: strike, expiration_date: expiry, open_interest: 50_000, dte: 202 }
  end

  # ── No data ──────────────────────────────────────────────────────────────────

  describe "when no trades exist today" do
    it "returns status :no_data" do
      expect(described_class.new(symbol, []).call[:status]).to eq(:no_data)
    end

    it "does not raise" do
      expect { described_class.new(symbol, []).call }.not_to raise_error
    end
  end

  # ── Call / Put premium totals ─────────────────────────────────────────────────

  describe "call_premium_total and put_premium_total" do
    before do
      make_flow(option_type: "Call", premium: 300_000)
      make_flow(option_type: "Call", premium: 200_000)
      make_flow(option_type: "Put",  premium: 150_000)
    end

    it "sums only Call premium" do
      expect(described_class.new(symbol, []).call[:call_premium_total]).to eq(500_000)
    end

    it "sums only Put premium" do
      expect(described_class.new(symbol, []).call[:put_premium_total]).to eq(150_000)
    end
  end

  # ── large_orders: top 20 by premium (fixed count, NOT large_premium flag) ────

  describe "large_orders" do
    context "fewer than 20 trades total" do
      before do
        make_flow(premium: 800_000, large_premium: true)
        make_flow(premium: 500_000, large_premium: true)
        make_flow(premium: 300_000, large_premium: false)   # below flag threshold, still enters榜
      end

      it "returns all trades sorted by premium desc (no flag filter)" do
        orders = described_class.new(symbol, []).call[:large_orders]
        expect(orders.map { |t| t[:premium] }).to eq([800_000, 500_000, 300_000])
      end

      it "includes trades regardless of large_premium flag value" do
        orders = described_class.new(symbol, []).call[:large_orders]
        expect(orders.size).to eq(3)
      end
    end

    context "edge case: more than 20 trades exist, some large_premium=true" do
      before do
        # 25 trades; premiums 100k, 200k, …, 2500k
        # The top 20 by premium are 600k–2500k; trades below 500k must be excluded
        25.times do |i|
          make_flow(premium: (i + 1) * 100_000, large_premium: (i + 1) * 100_000 >= 500_000)
        end
      end

      it "returns exactly 20 trades even when more than 20 large_premium=true exist" do
        orders = described_class.new(symbol, []).call[:large_orders]
        expect(orders.size).to eq(20)
      end

      it "returns the 20 highest-premium trades, not filtered by flag" do
        orders   = described_class.new(symbol, []).call[:large_orders]
        premiums = orders.map { |t| t[:premium] }
        expect(premiums.min).to eq(600_000)   # 25th–21st place (100k–500k) are excluded
        expect(premiums.max).to eq(2_500_000)
      end

      it "is sorted by premium descending" do
        orders   = described_class.new(symbol, []).call[:large_orders]
        premiums = orders.map { |t| t[:premium] }
        expect(premiums).to eq(premiums.sort.reverse)
      end
    end

    context "edge case: 0 trades have large_premium=true" do
      before do
        3.times { |i| make_flow(premium: (i + 1) * 100_000, large_premium: false) }
      end

      it "still returns the top trades by premium even when large_premium is always false" do
        orders = described_class.new(symbol, []).call[:large_orders]
        expect(orders.size).to eq(3)
        expect(orders.first[:premium]).to eq(300_000)
      end
    end
  end

  # ── Cross-reference highlighted trades ───────────────────────────────────────

  describe "highlighted_trades" do
    let(:target_expiry)  { Date.current + 202 }
    let(:target_strike)  { 10.0 }
    let(:candidates) do
      [
        candidate(strike: target_strike, expiry: target_expiry),
        candidate(strike: 12.0, expiry: target_expiry)
      ]
    end

    before do
      make_flow(strike: target_strike, expires_at: target_expiry, premium: 600_000)
      make_flow(strike: 15.0, expires_at: target_expiry, premium: 400_000)
      make_flow(strike: target_strike, expires_at: target_expiry + 90, premium: 200_000)
    end

    it "includes only trades matching a top-N candidate on (strike, expiry)" do
      result = described_class.new(symbol, candidates, top_n: 5).call
      expect(result[:highlighted_trades].size).to eq(1)
    end

    it "records correct rank and candidate strike/expiry" do
      match = described_class.new(symbol, candidates, top_n: 5).call[:highlighted_trades].first
      expect(match[:rank]).to eq(1)
      expect(match[:candidate_strike].to_f).to eq(target_strike)
    end
  end

  # ── Non-ranking guarantee ─────────────────────────────────────────────────────

  describe "non-ranking guarantee" do
    it "does not modify the ranked_candidates array" do
      make_flow(premium: 300_000)
      candidates  = [ candidate(strike: 10.0, expiry: Date.current + 202) ]
      before_call = candidates.dup
      described_class.new(symbol, candidates).call
      expect(candidates).to eq(before_call)
    end
  end
end
