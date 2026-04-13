require "rails_helper"

RSpec.describe WatchlistItem, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:watchlist_item)).to be_valid
    end

    it "is invalid without symbol" do
      expect(build(:watchlist_item, symbol: nil)).not_to be_valid
    end

    it "is invalid when symbol is duplicated (case-insensitive)" do
      create(:watchlist_item, symbol: "AAPL")
      expect(build(:watchlist_item, symbol: "aapl")).not_to be_valid
    end

    it "is invalid when symbol contains illegal characters" do
      expect(build(:watchlist_item, symbol: "A B")).not_to be_valid
    end

    it "is invalid when symbol exceeds 10 characters" do
      expect(build(:watchlist_item, symbol: "A" * 11)).not_to be_valid
    end

    it "accepts symbols with dots and hyphens" do
      expect(build(:watchlist_item, symbol: "BRK.B")).to be_valid
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  describe "before_validation: upcase and strip symbol" do
    it "upcases symbol before validation" do
      item = create(:watchlist_item, symbol: "tsla")
      expect(item.symbol).to eq("TSLA")
    end

    it "strips whitespace from symbol" do
      item = create(:watchlist_item, symbol: " aapl ")
      expect(item.symbol).to eq("AAPL")
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".ordered" do
    it "orders by position then created_at" do
      # Use high positions to avoid conflicts with any pre-existing test DB records
      second = create(:watchlist_item, symbol: "TSLA", position: 9998)
      first  = create(:watchlist_item, symbol: "AAPL", position: 9997)
      subset = described_class.ordered.where(id: [ first.id, second.id ])
      expect(subset.first).to eq(first)
      expect(subset.last).to  eq(second)
    end
  end

  # ── Class methods ────────────────────────────────────────────────────────────

  describe ".next_position" do
    it "returns current_max + 1 with no additional records" do
      expected = described_class.maximum(:position).to_i + 1
      expect(described_class.next_position).to eq(expected)
    end

    it "accounts for a newly created record with higher position" do
      current_max = described_class.maximum(:position).to_i
      create(:watchlist_item, symbol: "ZZZZ", position: current_max + 10)
      expect(described_class.next_position).to eq(current_max + 11)
    end
  end
end
