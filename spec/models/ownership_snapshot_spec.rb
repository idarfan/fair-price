require "rails_helper"

RSpec.describe OwnershipSnapshot, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:ownership_snapshot)).to be_valid
    end

    it "requires ticker" do
      expect(build(:ownership_snapshot, ticker: nil)).not_to be_valid
    end

    it "requires quarter" do
      expect(build(:ownership_snapshot, quarter: nil)).not_to be_valid
    end

    it "requires snapshot_date" do
      expect(build(:ownership_snapshot, snapshot_date: nil)).not_to be_valid
    end

    it "enforces uniqueness of quarter scoped to ticker" do
      create(:ownership_snapshot, ticker: "WULF", quarter: "2025-Q4")
      expect(build(:ownership_snapshot, ticker: "WULF", quarter: "2025-Q4")).not_to be_valid
    end

    it "allows same quarter for different tickers" do
      create(:ownership_snapshot, ticker: "AAPL", quarter: "2025-Q4")
      expect(build(:ownership_snapshot, ticker: "MSFT", quarter: "2025-Q4")).to be_valid
    end
  end

  describe "associations" do
    it "destroys holders when snapshot is destroyed" do
      snapshot = create(:ownership_snapshot)
      create(:ownership_holder, ownership_snapshot: snapshot)
      create(:ownership_holder, ownership_snapshot: snapshot)
      expect { snapshot.destroy }.to change(OwnershipHolder, :count).by(-2)
    end
  end

  describe ".for_ticker" do
    it "returns snapshots for the given ticker ordered by snapshot_date" do
      old = create(:ownership_snapshot, ticker: "WULF", quarter: "2025-Q3", snapshot_date: 3.months.ago.to_date)
      new = create(:ownership_snapshot, ticker: "WULF", quarter: "2025-Q4", snapshot_date: Date.current)
      create(:ownership_snapshot, ticker: "AAPL", quarter: "2025-Q4")

      result = OwnershipSnapshot.for_ticker("WULF")
      expect(result).to eq([old, new])
    end

    it "is case-insensitive for ticker" do
      snap = create(:ownership_snapshot, ticker: "WULF", quarter: "2025-Q4")
      expect(OwnershipSnapshot.for_ticker("wulf")).to include(snap)
    end
  end
end
