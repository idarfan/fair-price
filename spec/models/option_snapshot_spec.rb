require "rails_helper"

RSpec.describe OptionSnapshot, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:option_snapshot)).to be_valid
    end

    it "is invalid without snapshot_date" do
      expect(build(:option_snapshot, snapshot_date: nil)).not_to be_valid
    end

    it "is invalid without contract_symbol" do
      expect(build(:option_snapshot, contract_symbol: nil)).not_to be_valid
    end

    it "is invalid without option_type" do
      expect(build(:option_snapshot, option_type: nil)).not_to be_valid
    end

    it "is invalid without expiration" do
      expect(build(:option_snapshot, expiration: nil)).not_to be_valid
    end

    it "is invalid without strike" do
      expect(build(:option_snapshot, strike: nil)).not_to be_valid
    end

    it "is invalid with unknown option_type" do
      expect(build(:option_snapshot, option_type: "straddle")).not_to be_valid
    end

    it "accepts 'call' option_type" do
      expect(build(:option_snapshot, option_type: "call")).to be_valid
    end

    it "accepts 'put' option_type" do
      expect(build(:option_snapshot, option_type: "put")).to be_valid
    end
  end

  # ── Associations ─────────────────────────────────────────────────────────────

  describe "associations" do
    it "belongs to tracked_ticker" do
      ticker   = create(:tracked_ticker)
      snapshot = create(:option_snapshot, tracked_ticker: ticker)
      expect(snapshot.tracked_ticker).to eq(ticker)
    end

    it "is invalid without tracked_ticker" do
      snapshot = build(:option_snapshot, tracked_ticker: nil)
      expect(snapshot).not_to be_valid
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".puts" do
    it "returns only put options" do
      put_snap  = create(:option_snapshot, option_type: "put")
      call_snap = create(:option_snapshot, option_type: "call",
                         contract_symbol: "AAPL230120C00150000")
      expect(described_class.puts).to include(put_snap)
      expect(described_class.puts).not_to include(call_snap)
    end
  end

  describe ".calls" do
    it "returns only call options" do
      put_snap  = create(:option_snapshot, option_type: "put")
      call_snap = create(:option_snapshot, option_type: "call",
                         contract_symbol: "AAPL230120C00150000")
      expect(described_class.calls).to include(call_snap)
      expect(described_class.calls).not_to include(put_snap)
    end
  end

  describe ".for_expiration" do
    it "returns snapshots matching the given expiration date" do
      target = create(:option_snapshot, expiration: Date.today + 30)
      other  = create(:option_snapshot, expiration: Date.today + 60,
                      contract_symbol: "AAPL230120C00150000")
      expect(described_class.for_expiration(Date.today + 30)).to include(target)
      expect(described_class.for_expiration(Date.today + 30)).not_to include(other)
    end
  end

  describe ".recent_days" do
    it "includes snapshots within the window" do
      recent = create(:option_snapshot, snapshot_date: Date.today - 10)
      old    = create(:option_snapshot, snapshot_date: Date.today - 90,
                      contract_symbol: "AAPL230120C00150000")
      expect(described_class.recent_days(60)).to include(recent)
      expect(described_class.recent_days(60)).not_to include(old)
    end
  end

  describe ".near_strike" do
    it "includes snapshots within the given price range" do
      near = create(:option_snapshot, strike: 150.0)
      far  = create(:option_snapshot, strike: 250.0,
                    contract_symbol: "AAPL230120C00250000")
      results = described_class.near_strike(150.0, range: 0.1)
      expect(results).to include(near)
      expect(results).not_to include(far)
    end
  end

  # ── Class methods ─────────────────────────────────────────────────────────────

  describe ".premium_trend" do
    it "returns snapshots ordered by snapped_at for the given contract params" do
      ticker = create(:tracked_ticker)
      exp    = Date.today + 30
      t1     = create(:option_snapshot, tracked_ticker: ticker, strike: 150.0,
                      expiration: exp, option_type: "put",
                      snapped_at: 2.hours.ago, contract_symbol: "AAPL_1")
      t2     = create(:option_snapshot, tracked_ticker: ticker, strike: 150.0,
                      expiration: exp, option_type: "put",
                      snapped_at: 1.hour.ago,  contract_symbol: "AAPL_2")
      _other = create(:option_snapshot, tracked_ticker: ticker, strike: 200.0,
                      expiration: exp, option_type: "put", contract_symbol: "AAPL_3")

      trend = OptionSnapshot.premium_trend(
        ticker_id: ticker.id, strike: 150.0,
        expiration: exp, option_type: "put"
      )
      expect(trend.to_a).to eq([ t1, t2 ])
    end
  end
end
