require "rails_helper"

RSpec.describe OwnershipSnapshotService do
  subject(:service) { described_class.new }

  let(:ticker) { "WULF" }
  let(:data) do
    {
      summary: {
        institutions_pct:   42.3,
        insiders_pct:        8.7,
        institutions_count: 156
      },
      top_holders: [
        { name: "Vanguard", pct_held: 9.82, value: 494_000_000, report_date: "2025-12-31" },
        { name: "BlackRock", pct_held: 7.15, value: 409_000_000, report_date: "2025-12-31" }
      ]
    }
  end

  describe "#current_quarter" do
    it "returns a string in YYYY-QN format" do
      result = service.current_quarter
      expect(result).to match(/\A\d{4}-Q[1-4]\z/)
    end

    it "returns the correct quarter for the current month" do
      allow(Date).to receive(:current).and_return(Date.new(2025, 4, 1))
      expect(service.current_quarter).to eq("2025-Q2")
    end
  end

  describe "#save_snapshot" do
    it "creates a new snapshot and holders" do
      expect {
        service.save_snapshot(ticker, data)
      }.to change(OwnershipSnapshot, :count).by(1)
        .and change(OwnershipHolder, :count).by(2)
    end

    it "stores the correct summary data" do
      snapshot = service.save_snapshot(ticker, data)
      expect(snapshot.institutional_pct.to_f).to eq(42.3)
      expect(snapshot.insider_pct.to_f).to eq(8.7)
      expect(snapshot.institution_count).to eq(156)
    end

    it "stores holder details correctly" do
      snapshot = service.save_snapshot(ticker, data)
      holder   = snapshot.ownership_holders.find_by(name: "Vanguard")
      expect(holder.pct.to_f).to eq(9.82)
      expect(holder.market_value).to eq(494_000_000)
    end

    it "upserts an existing snapshot for the same quarter" do
      service.save_snapshot(ticker, data)
      updated_data = data.merge(summary: data[:summary].merge(institutions_pct: 50.0))

      expect {
        service.save_snapshot(ticker, updated_data)
      }.not_to change(OwnershipSnapshot, :count)

      snapshot = OwnershipSnapshot.for_ticker(ticker).last
      expect(snapshot.institutional_pct.to_f).to eq(50.0)
    end

    it "replaces holders on upsert" do
      service.save_snapshot(ticker, data)
      new_data = data.merge(top_holders: [{ name: "ARK", pct_held: 2.56, value: 152_000_000, report_date: "2025-12-31" }])
      service.save_snapshot(ticker, new_data)

      snapshot = OwnershipSnapshot.for_ticker(ticker).last
      expect(snapshot.ownership_holders.count).to eq(1)
      expect(snapshot.ownership_holders.first.name).to eq("ARK")
    end

    it "is case-insensitive for ticker" do
      snapshot = service.save_snapshot("wulf", data)
      expect(snapshot.ticker).to eq("WULF")
    end
  end

  describe "#load_history" do
    it "returns snapshots for the ticker within the date range" do
      old = create(:ownership_snapshot, ticker: ticker, quarter: "2024-Q4", snapshot_date: 2.years.ago.to_date)
      recent = create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q4", snapshot_date: Date.current)

      result = service.load_history(ticker, since: 1.year.ago.to_date)
      expect(result).to include(recent)
      expect(result).not_to include(old)
    end
  end

  describe "#previous_snapshot" do
    it "returns the snapshot before the given one" do
      old  = create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q3", snapshot_date: 3.months.ago.to_date)
      curr = create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q4", snapshot_date: Date.current)

      expect(service.previous_snapshot(ticker, before_snapshot: curr)).to eq(old)
    end

    it "returns nil when there is only one snapshot" do
      snap = create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q4")
      expect(service.previous_snapshot(ticker, before_snapshot: snap)).to be_nil
    end
  end
end
