require "rails_helper"

RSpec.describe Portfolio, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:portfolio)).to be_valid
    end

    it "is invalid without symbol" do
      expect(build(:portfolio, symbol: nil)).not_to be_valid
    end

    it "is invalid when symbol format is wrong" do
      expect(build(:portfolio, symbol: "A B C")).not_to be_valid
    end

    it "is invalid when shares is zero" do
      expect(build(:portfolio, shares: 0)).not_to be_valid
    end

    it "is invalid when shares is negative" do
      expect(build(:portfolio, shares: -1)).not_to be_valid
    end

    it "is invalid when unit_cost is zero" do
      expect(build(:portfolio, unit_cost: 0)).not_to be_valid
    end

    it "is invalid when sell_price is zero" do
      expect(build(:portfolio, sell_price: 0)).not_to be_valid
    end

    it "is valid when sell_price is nil (not yet sold)" do
      expect(build(:portfolio, sell_price: nil)).to be_valid
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  describe "before_validation: upcase and strip symbol" do
    it "upcases symbol" do
      holding = create(:portfolio, symbol: "msft")
      expect(holding.symbol).to eq("MSFT")
    end

    it "strips whitespace from symbol" do
      holding = create(:portfolio, symbol: " nvda ")
      expect(holding.symbol).to eq("NVDA")
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".ordered" do
    it "orders by position then created_at" do
      second = create(:portfolio, symbol: "MSFT", position: 2)
      first  = create(:portfolio, symbol: "AAPL", position: 1)
      expect(described_class.ordered.first).to eq(first)
      expect(described_class.ordered.second).to eq(second)
    end
  end

  # ── Class methods ────────────────────────────────────────────────────────────

  describe ".next_position" do
    it "returns 1 when no holdings exist" do
      expect(described_class.next_position).to eq(1)
    end

    it "returns max position + 1" do
      create(:portfolio, symbol: "AAPL", position: 3)
      expect(described_class.next_position).to eq(4)
    end
  end

  # ── Instance methods ─────────────────────────────────────────────────────────

  describe "#total_cost" do
    it "returns shares × unit_cost" do
      holding = build(:portfolio, shares: 10, unit_cost: 150.0)
      expect(holding.total_cost).to eq(1500.0)
    end
  end

  describe "#profit_if_sold" do
    it "returns nil when sell_price is nil" do
      holding = build(:portfolio, sell_price: nil)
      expect(holding.profit_if_sold).to be_nil
    end

    it "returns positive profit when sell_price > unit_cost" do
      holding = build(:portfolio, shares: 10, unit_cost: 100.0, sell_price: 120.0)
      expect(holding.profit_if_sold).to eq(200.0)
    end

    it "returns negative profit when sell_price < unit_cost" do
      holding = build(:portfolio, shares: 10, unit_cost: 100.0, sell_price: 80.0)
      expect(holding.profit_if_sold).to eq(-200.0)
    end
  end
end
