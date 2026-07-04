# frozen_string_literal: true

require "rails_helper"

RSpec.describe StrikeChainSnapshot, type: :model do
  let(:snap) do
    described_class.new(
      symbol:     "NOK",
      strikes:    [ 6.5, 7.0, 7.5 ],
      spot_price: 12.07,
      scraped_at: Time.current
    )
  end

  describe "#valid_strike?" do
    it "accepts strikes within range" do
      expect(snap.valid_strike?(7.0)).to be true
    end

    it "accepts strikes within one spacing of min" do
      expect(snap.valid_strike?(6.0)).to be true  # tolerance = 0.5
    end

    it "accepts strikes within one spacing of max" do
      expect(snap.valid_strike?(8.0)).to be true  # tolerance = 0.5
    end

    it "rejects strikes more than one spacing below min" do
      expect(snap.valid_strike?(5.0)).to be false  # min=6.5, tol=0.5 → threshold=6.0
    end

    it "rejects strikes more than one spacing above max" do
      expect(snap.valid_strike?(10.0)).to be false  # max=7.5, tol=0.5 → threshold=8.0
    end
  end

  describe "#invalid_message" do
    it "includes symbol, strike, and actual range" do
      msg = snap.invalid_message("NOK", 2.0)
      expect(msg).to include("NOK")
      expect(msg).to include("2.0")
      expect(msg).to include("6.50")
      expect(msg).to include("7.50")
      expect(msg).to include("12.07")
    end
  end

  describe "with single strike" do
    let(:single) do
      described_class.new(symbol: "X", strikes: [ 10.0 ], spot_price: 10.5, scraped_at: Time.current)
    end

    it "uses 10% fallback tolerance" do
      expect(single.valid_strike?(9.05)).to be true   # 10.0 * 0.10 = 1.0 → lower = 9.0
      expect(single.valid_strike?(7.0)).to be false
    end
  end

  describe "upsert via persist_chain_snapshot" do
    it "writes and overwrites the snapshot for the same symbol" do
      svc = BarchartScraperService.new("TEST")
      data1 = { "chain_snapshot" => { "strikes" => [ 5.0, 6.0 ], "spot_price" => 10.0 } }
      svc.send(:persist_chain_snapshot, data1)

      snap1 = described_class.find_by(symbol: "TEST")
      expect(snap1.strikes).to eq([ 5.0, 6.0 ])
      expect(snap1.spot_price.to_f).to eq(10.0)

      data2 = { "chain_snapshot" => { "strikes" => [ 5.0, 6.0, 7.0 ], "spot_price" => 11.0 } }
      svc.send(:persist_chain_snapshot, data2)

      snap2 = described_class.find_by(symbol: "TEST")
      expect(snap2.strikes).to eq([ 5.0, 6.0, 7.0 ])
      expect(snap2.spot_price.to_f).to eq(11.0)
      expect(described_class.where(symbol: "TEST").count).to eq(1)
    end

    it "skips when chain_snapshot is absent" do
      svc = BarchartScraperService.new("SKIP")
      expect { svc.send(:persist_chain_snapshot, {}) }.not_to raise_error
      expect(described_class.where(symbol: "SKIP").count).to eq(0)
    end
  end
end
