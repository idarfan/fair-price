require "rails_helper"

RSpec.describe PriceAlert, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:price_alert)).to be_valid
    end

    it "is invalid without symbol" do
      expect(build(:price_alert, symbol: nil)).not_to be_valid
    end

    it "is invalid without target_price" do
      expect(build(:price_alert, target_price: nil)).not_to be_valid
    end

    it "is invalid when target_price is zero" do
      expect(build(:price_alert, target_price: 0)).not_to be_valid
    end

    it "is invalid when target_price is negative" do
      expect(build(:price_alert, target_price: -1)).not_to be_valid
    end

    it "is invalid without condition" do
      expect(build(:price_alert, condition: nil)).not_to be_valid
    end

    it "is invalid with unknown condition" do
      expect(build(:price_alert, condition: "equal")).not_to be_valid
    end

    it "accepts 'above' as condition" do
      expect(build(:price_alert, condition: "above")).to be_valid
    end

    it "accepts 'below' as condition" do
      expect(build(:price_alert, condition: "below")).to be_valid
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  describe "before_save: upcase_symbol" do
    it "upcases symbol on save" do
      alert = create(:price_alert, symbol: "aapl")
      expect(alert.symbol).to eq("AAPL")
    end

    it "upcases on update too" do
      alert = create(:price_alert, symbol: "AAPL")
      alert.update!(symbol: "tsla")
      expect(alert.symbol).to eq("TSLA")
    end
  end

  describe "before_create: set_position" do
    it "assigns position 0 to the first record" do
      alert = create(:price_alert)
      expect(alert.position).to eq(0)
    end

    it "increments position for subsequent records" do
      create(:price_alert, symbol: "AAPL")
      second = create(:price_alert, symbol: "TSLA")
      expect(second.position).to eq(1)
    end
  end

  # ── Instance methods ─────────────────────────────────────────────────────────

  describe "#triggered?" do
    it "returns false when triggered_at is nil" do
      expect(build(:price_alert, triggered_at: nil).triggered?).to be(false)
    end

    it "returns true when triggered_at is present" do
      expect(build(:price_alert, triggered_at: Time.current).triggered?).to be(true)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".active" do
    it "returns only active alerts" do
      active   = create(:price_alert, active: true)
      inactive = create(:price_alert, symbol: "TSLA", active: false)
      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end
end
