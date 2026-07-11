# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccShortCallSnapshot, type: :model do
  describe "FRESH_WINDOW" do
    it "references LeapsOptionChainSnapshot::FRESH_WINDOW, not a second literal" do
      expect(described_class::FRESH_WINDOW).to equal(LeapsOptionChainSnapshot::FRESH_WINDOW)
    end
  end

  describe ".fresh scope / .fresh_for?" do
    after { described_class.where(symbol: "FWTEST").delete_all }

    it "true when a row was scraped within FRESH_WINDOW" do
      travel_to Time.current do
        create(:pmcc_short_call_snapshot, symbol: "FWTEST",
               scraped_at: (described_class::FRESH_WINDOW - 1.minute).ago)
        expect(described_class.fresh_for?("FWTEST")).to be true
      end
    end

    it "false when the only row is older than FRESH_WINDOW" do
      travel_to Time.current do
        create(:pmcc_short_call_snapshot, symbol: "FWTEST",
               scraped_at: (described_class::FRESH_WINDOW + 1.minute).ago)
        expect(described_class.fresh_for?("FWTEST")).to be false
      end
    end
  end

  describe "#mid_price" do
    it "returns the stored column value when present (persist-time decision wins)" do
      snap = build(:pmcc_short_call_snapshot, mid_price: 0.24, bid: 0.23, ask: 0.26)
      expect(snap.mid_price).to eq(0.24)
    end

    it "falls back to (bid+ask)/2 only when the stored column is nil" do
      snap = build(:pmcc_short_call_snapshot, mid_price: nil, bid: 0.23, ask: 0.27)
      expect(snap.mid_price).to be_within(0.0001).of(0.25)
    end

    it "returns nil when both mid_price and bid/ask are absent" do
      snap = build(:pmcc_short_call_snapshot, mid_price: nil, bid: nil, ask: nil)
      expect(snap.mid_price).to be_nil
    end
  end

  describe "validations" do
    it "requires symbol, expiration_date, strike, scraped_at" do
      # option_type has a DB default ("Call" — §5 DDL), so it's never blank
      # unless explicitly nulled; not part of this presence-failure assertion.
      snap = described_class.new
      expect(snap).not_to be_valid
      expect(snap.errors.attribute_names).to include(:symbol, :expiration_date, :strike, :scraped_at)
    end

    it "still enforces presence on option_type when explicitly nulled" do
      snap = build(:pmcc_short_call_snapshot, option_type: nil)
      expect(snap).not_to be_valid
      expect(snap.errors.attribute_names).to include(:option_type)
    end
  end
end
