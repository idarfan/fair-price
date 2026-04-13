require "rails_helper"

RSpec.describe TrackedTicker, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:tracked_ticker)).to be_valid
    end

    it "is invalid without symbol" do
      expect(build(:tracked_ticker, symbol: nil)).not_to be_valid
    end

    it "is invalid when symbol is duplicated (case-insensitive)" do
      create(:tracked_ticker, symbol: "AAPL")
      expect(build(:tracked_ticker, symbol: "aapl")).not_to be_valid
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  describe "before_save: upcase symbol" do
    it "upcases and strips symbol on save" do
      ticker = create(:tracked_ticker, symbol: " tsla ")
      expect(ticker.symbol).to eq("TSLA")
    end
  end

  # ── Associations ─────────────────────────────────────────────────────────────

  describe "associations" do
    it "has many option_snapshots" do
      ticker   = create(:tracked_ticker)
      snapshot = create(:option_snapshot, tracked_ticker: ticker)
      expect(ticker.option_snapshots).to include(snapshot)
    end

    it "destroys option_snapshots on delete" do
      ticker = create(:tracked_ticker)
      create(:option_snapshot, tracked_ticker: ticker)
      expect { ticker.destroy }.to change(OptionSnapshot, :count).by(-1)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".active" do
    it "returns only active tickers" do
      active   = create(:tracked_ticker, active: true)
      inactive = create(:tracked_ticker, active: false)
      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end

  # ── Config accessors ─────────────────────────────────────────────────────────

  describe "config accessors" do
    context "with explicit config values" do
      let(:ticker) { build(:tracked_ticker, config: { "min_dte" => 14, "max_dte" => 60, "strike_range" => 0.2 }) }

      it "returns min_dte from config" do
        expect(ticker.min_dte).to eq(14)
      end

      it "returns max_dte from config" do
        expect(ticker.max_dte).to eq(60)
      end

      it "returns strike_range from config" do
        expect(ticker.strike_range).to eq(0.2)
      end
    end

    context "with empty config (defaults)" do
      let(:ticker) { build(:tracked_ticker, config: {}) }

      it "defaults min_dte to 7" do
        expect(ticker.min_dte).to eq(7)
      end

      it "defaults max_dte to 90" do
        expect(ticker.max_dte).to eq(90)
      end

      it "defaults strike_range to 0.3" do
        expect(ticker.strike_range).to eq(0.3)
      end
    end
  end

  # ── Instance methods ─────────────────────────────────────────────────────────

  describe "#last_snapshot_date" do
    it "returns nil when there are no snapshots" do
      ticker = create(:tracked_ticker)
      expect(ticker.last_snapshot_date).to be_nil
    end

    it "returns the most recent snapshot_date" do
      ticker = create(:tracked_ticker)
      create(:option_snapshot, tracked_ticker: ticker, snapshot_date: Date.today - 3)
      create(:option_snapshot, tracked_ticker: ticker, snapshot_date: Date.today,
             contract_symbol: "AAPL230120C00150000", option_type: "call")
      expect(ticker.last_snapshot_date).to eq(Date.today)
    end
  end
end
