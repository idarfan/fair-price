require "rails_helper"

RSpec.describe OwnershipHolder, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:ownership_holder)).to be_valid
    end

    it "requires name" do
      expect(build(:ownership_holder, name: nil)).not_to be_valid
    end

    it "enforces uniqueness of name scoped to ownership_snapshot" do
      snapshot = create(:ownership_snapshot)
      create(:ownership_holder, ownership_snapshot: snapshot, name: "Vanguard")
      expect(build(:ownership_holder, ownership_snapshot: snapshot, name: "Vanguard")).not_to be_valid
    end

    it "allows same name for different snapshots" do
      snap1 = create(:ownership_snapshot, ticker: "AAPL", quarter: "2025-Q4")
      snap2 = create(:ownership_snapshot, ticker: "MSFT", quarter: "2025-Q4")
      create(:ownership_holder, ownership_snapshot: snap1, name: "Vanguard")
      expect(build(:ownership_holder, ownership_snapshot: snap2, name: "Vanguard")).to be_valid
    end
  end

  describe "associations" do
    it "belongs to an ownership_snapshot" do
      holder = create(:ownership_holder)
      expect(holder.ownership_snapshot).to be_a(OwnershipSnapshot)
    end
  end
end
