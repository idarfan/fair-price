require "rails_helper"

RSpec.describe "Api::V1::OwnershipSnapshots", type: :request do
  let(:ticker) { "WULF" }

  describe "GET /api/v1/ownership_snapshots/:ticker" do
    context "with no snapshots" do
      it "returns 200 with empty snapshots array" do
        get "/api/v1/ownership_snapshots/#{ticker}"
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["snapshots"]).to eq([])
        expect(json["previous"]).to be_nil
      end
    end

    context "with multiple snapshots" do
      let!(:old_snap) do
        snap = create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q3",
                      snapshot_date: 45.days.ago.to_date)
        create(:ownership_holder, ownership_snapshot: snap, name: "Vanguard", pct: 9.82)
        snap
      end
      let!(:new_snap) do
        create(:ownership_snapshot, ticker: ticker, quarter: "2025-Q4",
               snapshot_date: Date.current)
      end

      it "returns snapshots with correct structure" do
        get "/api/v1/ownership_snapshots/#{ticker}"
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["snapshots"].length).to eq(2)

        first = json["snapshots"].first
        expect(first.keys).to include("quarter", "date", "institutional_pct", "insider_pct",
                                      "institution_count", "holders")
      end

      it "includes holders in each snapshot" do
        get "/api/v1/ownership_snapshots/#{ticker}"
        json = JSON.parse(response.body)
        snapshot_with_holders = json["snapshots"].find { |s| s["holders"].any? }
        holder = snapshot_with_holders["holders"].first
        expect(holder.keys).to include("name", "pct", "value", "filing_date", "pct_change")
      end

      it "filters by range=1w" do
        get "/api/v1/ownership_snapshots/#{ticker}?range=1w"
        json = JSON.parse(response.body)
        # old_snap is 45 days ago, should be excluded from 1w range
        expect(json["snapshots"].length).to eq(1)
        expect(json["snapshots"].first["quarter"]).to eq("2025-Q4")
      end

      it "includes previous snapshot" do
        get "/api/v1/ownership_snapshots/#{ticker}"
        json = JSON.parse(response.body)
        expect(json["previous"]).not_to be_nil
        expect(json["previous"]["quarter"]).to eq("2025-Q3")
      end
    end
  end

  describe "POST /api/v1/ownership_snapshots/:ticker" do
    let(:holders_data) do
      [{ name: "Vanguard", pct_held: 9.82, value: 494_000_000, report_date: "2025-12-31" }]
    end
    let(:fetch_result) do
      {
        summary:     { institutions_pct: 42.3, insiders_pct: 8.7, institutions_count: 156 },
        top_holders: holders_data,
        source:      "yahoo_finance"
      }
    end

    context "when data is available" do
      before do
        allow_any_instance_of(YahooFinanceService).to receive(:holders).and_return(fetch_result)
      end

      it "returns 201 with snapshot data" do
        post "/api/v1/ownership_snapshots/#{ticker}",
             params: {}, headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["snapshot"]["institutional_pct"]).to eq(42.3)
        expect(json["snapshot"]["holders"].length).to eq(1)
      end

      it "persists the snapshot to the database" do
        expect {
          post "/api/v1/ownership_snapshots/#{ticker}"
        }.to change(OwnershipSnapshot, :count).by(1)
      end
    end

    context "when data is unavailable" do
      before do
        allow_any_instance_of(YahooFinanceService).to receive(:holders).and_return(nil)
        allow_any_instance_of(SecEdgarService).to receive(:holders).and_return(nil)
      end

      it "returns 422 with error message" do
        post "/api/v1/ownership_snapshots/#{ticker}"
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to include(ticker)
      end
    end
  end
end
