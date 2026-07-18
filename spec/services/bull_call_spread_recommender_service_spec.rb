# frozen_string_literal: true

require "rails_helper"

RSpec.describe BullCallSpreadRecommenderService do
  let(:k1)     { 70.0 }
  let(:k1_ask) { 8.00 }

  # width=10 target r=0.60 -> debit=6.0 -> k2_bid = k1_ask-6.0 = 2.0
  # width=10 target r=0.50 -> debit=5.0 -> k2_bid = 3.0
  # width=15 target r=0.35 -> debit=5.25 -> k2_bid = 2.75
  let(:candidates) do
    [
      { "strike" => 80.0, "bid" => 2.0,  "ask" => 2.2, "open_interest" => 50 },   # r=0.60
      { "strike" => 82.0, "bid" => 3.0,  "ask" => 3.2, "open_interest" => 40 },   # width=12, debit=5.0, r=0.4167
      { "strike" => 85.0, "bid" => 2.75, "ask" => 3.0, "open_interest" => 30 },   # width=15, debit=5.25, r=0.35
      { "strike" => 60.0, "bid" => 10.0, "ask" => 10.2, "open_interest" => 20 }   # below K1, excluded
    ]
  end

  describe "#call" do
    it "picks the closest ratio candidate for each tab" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates).call

      expect(tabs[:conservative][:k2]).to eq(80.0)
      expect(tabs[:aggressive][:k2]).to eq(85.0)
      expect(tabs.values.map { |t| t[:k2] }.uniq.length).to eq(tabs.size)
    end

    it "excludes candidates at or below K1" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates).call
      expect(tabs.values.map { |t| t[:k2] }).not_to include(60.0)
    end

    it "excludes candidates with zero bid or zero open interest" do
      dirty = candidates + [
        { "strike" => 90.0, "bid" => 0,   "ask" => 1.0, "open_interest" => 100 },
        { "strike" => 92.0, "bid" => 1.0, "ask" => 1.2, "open_interest" => 0 }
      ]
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: dirty).call
      expect(tabs.values.map { |t| t[:k2] }).not_to include(90.0, 92.0)
    end

    it "reassigns to the next-closest unused candidate when tabs would collide" do
      # Only two usable candidates for three tabs: whichever ties/collides must
      # fall back to the next-nearest remaining strike instead of duplicating.
      tight_candidates = [
        { "strike" => 80.0, "bid" => 2.0, "ask" => 2.2, "open_interest" => 50 },  # r=0.60
        { "strike" => 81.0, "bid" => 2.2, "ask" => 2.4, "open_interest" => 50 }   # width=11 debit=5.8 r=0.527
      ]
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: tight_candidates).call

      chosen_k2s = tabs.values.map { |t| t[:k2] }
      expect(chosen_k2s.uniq.length).to eq(chosen_k2s.length)
      expect(tabs.size).to eq(2) # only 2 usable candidates available
    end

    it "returns full economics for each tab via the calculator service" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates).call
      conservative = tabs[:conservative][:result]

      expect(conservative.k1).to eq(k1)
      expect(conservative.k2).to eq(80.0)
      expect(conservative.max_profit).not_to be_nil
      expect(conservative.warning).to be_nil
    end

    it "includes S* and naked-buy comparison figures on every tab's result" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates).call
      conservative = tabs[:conservative][:result]

      expect(conservative.s_star).to eq(82.0)
      expect(conservative.naked_cost).to eq(800.0)
      expect(conservative.naked_breakeven).to eq(78.0)
      expect(conservative.spread_max_value).to eq(1000.0)
    end

    it "passes k1_bid through to the calculator so closeout_value can be computed" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates, k1_bid: 7.80).call
      conservative = tabs[:conservative][:result]

      # k1_bid=7.80, k2_ask (candidate at 80.0)=2.2 -> closeout = (7.80-2.2)*100
      expect(conservative.closeout_value).to eq(((7.80 - 2.2) * 100).round(2))
      expect(conservative.realized_pct).not_to be_nil
    end

    it "leaves closeout_value nil when k1_bid is not given" do
      tabs = described_class.new(k1: k1, k1_ask: k1_ask, candidates: candidates).call
      expect(tabs[:conservative][:result].closeout_value).to be_nil
    end
  end
end
