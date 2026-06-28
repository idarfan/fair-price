require "rails_helper"

RSpec.describe LeapsOptionsFlowPanelService do
  include ActiveSupport::Testing::TimeHelpers

  around { |ex| freeze_time { ex.run } }

  let(:symbol) { "NOK" }

  def make_flow(attrs = {})
    create(:options_flow_trade, { symbol: symbol, snapshot_date: Date.current }.merge(attrs))
  end

  # Minimal ranked candidates fixture — service only reads :strike / :expiration_date
  def candidate(strike:, expiry:)
    { strike: strike, expiration_date: expiry, open_interest: 50_000, dte: 202 }
  end

  # ── No data ──────────────────────────────────────────────────────────────────

  describe "when no trades exist today" do
    it "returns status :no_data" do
      result = described_class.new(symbol, []).call
      expect(result[:status]).to eq(:no_data)
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
      result = described_class.new(symbol, []).call
      expect(result[:call_premium_total]).to eq(500_000)
    end

    it "sums only Put premium" do
      result = described_class.new(symbol, []).call
      expect(result[:put_premium_total]).to eq(150_000)
    end

    it "does not mix Call and Put in each total" do
      result = described_class.new(symbol, []).call
      expect(result[:call_premium_total] + result[:put_premium_total]).to eq(650_000)
    end
  end

  # ── Large orders ─────────────────────────────────────────────────────────────

  describe "large_orders" do
    before do
      make_flow(premium: 800_000, large_premium: true)
      make_flow(premium: 500_000, large_premium: true)
      make_flow(premium: 300_000, large_premium: false)  # excluded
    end

    it "includes only large_premium trades" do
      result = described_class.new(symbol, []).call
      expect(result[:large_orders].size).to eq(2)
    end

    it "excludes non-large trades" do
      result = described_class.new(symbol, []).call
      premiums = result[:large_orders].map { |t| t[:premium] }
      expect(premiums).not_to include(300_000)
    end

    it "sorts large orders by premium descending" do
      result = described_class.new(symbol, []).call
      premiums = result[:large_orders].map { |t| t[:premium] }
      expect(premiums).to eq([ 800_000, 500_000 ])
    end
  end

  # ── Cross-reference highlighted trades ───────────────────────────────────────

  describe "highlighted_trades" do
    let(:target_expiry) { Date.current + 202 }
    let(:target_strike) { 10.0 }

    let(:candidates) do
      [
        candidate(strike: target_strike, expiry: target_expiry),  # rank 1
        candidate(strike: 12.0, expiry: target_expiry)            # rank 2
      ]
    end

    before do
      # Matches rank-1 candidate (same strike + expiry)
      make_flow(strike: target_strike, expires_at: target_expiry, premium: 600_000)
      # Different strike — should NOT appear in highlighted
      make_flow(strike: 15.0, expires_at: target_expiry, premium: 400_000)
      # Different expiry — should NOT appear
      make_flow(strike: target_strike, expires_at: target_expiry + 90, premium: 200_000)
    end

    it "includes only trades matching a top-N candidate on (strike, expiry)" do
      result = described_class.new(symbol, candidates, top_n: 5).call
      expect(result[:highlighted_trades].size).to eq(1)
    end

    it "records the correct rank and candidate strike/expiry" do
      match = described_class.new(symbol, candidates, top_n: 5).call[:highlighted_trades].first
      expect(match[:rank]).to eq(1)
      expect(match[:candidate_strike].to_f).to eq(target_strike)
      expect(match[:candidate_expiry].to_date).to eq(target_expiry)
    end

    it "does not affect the ranked_candidates order (no side-effects)" do
      original_order = candidates.map { |c| c[:strike].to_f }
      described_class.new(symbol, candidates, top_n: 5).call
      expect(candidates.map { |c| c[:strike].to_f }).to eq(original_order)
    end
  end

  # ── Panel does not influence ranking (contract test) ─────────────────────────

  describe "non-ranking guarantee" do
    it "returns the ranked_candidates array unchanged after call" do
      make_flow(premium: 300_000)
      candidates = [ candidate(strike: 10.0, expiry: Date.current + 202) ]
      before_call = candidates.dup

      described_class.new(symbol, candidates).call

      expect(candidates).to eq(before_call)
    end
  end
end
