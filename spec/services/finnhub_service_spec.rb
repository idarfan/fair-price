require "rails_helper"

RSpec.describe FinnhubService do
  subject(:service) { described_class.new(api_key: "test_key") }

  # ── Helper to build a stubbed HTTParty response ──────────────────────────────

  def stub_get(body:, success: true, code: 200)
    response = instance_double(HTTParty::Response,
                               success?:          success,
                               code:              code,
                               parsed_response:   body)
    allow(HTTParty).to receive(:get).and_return(response)
    response
  end

  # ── #quote ───────────────────────────────────────────────────────────────────

  describe "#quote" do
    let(:quote_payload) do
      { "c" => 182.5, "d" => 1.2, "dp" => 0.66, "h" => 184.0, "l" => 180.0,
        "o" => 181.0, "pc" => 181.3, "t" => 1_700_000_000 }
    end

    it "returns parsed response on success" do
      stub_get(body: quote_payload)
      result = service.quote("AAPL")
      expect(result["c"]).to eq(182.5)
    end

    it "calls the correct endpoint" do
      stub_get(body: quote_payload)
      service.quote("aapl")
      expect(HTTParty).to have_received(:get).with(
        "#{FinnhubService::BASE_URL}/quote",
        hash_including(query: hash_including(symbol: "AAPL", token: "test_key"))
      )
    end

    it "upcases the symbol" do
      stub_get(body: quote_payload)
      service.quote("tsla")
      expect(HTTParty).to have_received(:get).with(
        anything, hash_including(query: hash_including(symbol: "TSLA"))
      )
    end

    it "returns nil on HTTP failure" do
      stub_get(body: nil, success: false, code: 429)
      expect(service.quote("AAPL")).to be_nil
    end

    it "returns nil on network error" do
      allow(HTTParty).to receive(:get).and_raise(SocketError, "connection failed")
      expect(service.quote("AAPL")).to be_nil
    end

    it "returns nil on timeout" do
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)
      expect(service.quote("AAPL")).to be_nil
    end
  end

  # ── #earnings_calendar ───────────────────────────────────────────────────────

  describe "#earnings_calendar" do
    let(:earnings_payload) do
      {
        "earningsCalendar" => [
          { "symbol" => "AAPL", "date" => "2024-02-01", "epsEstimate" => 2.1 }
        ]
      }
    end

    it "returns the earningsCalendar array" do
      stub_get(body: earnings_payload)
      result = service.earnings_calendar(from_date: "2024-01-01", to_date: "2024-01-31")
      expect(result).to be_an(Array)
      expect(result.first["symbol"]).to eq("AAPL")
    end

    it "returns empty array when API returns nil" do
      stub_get(body: nil, success: false)
      result = service.earnings_calendar(from_date: "2024-01-01", to_date: "2024-01-31")
      expect(result).to eq([])
    end
  end

  # ── #market_news ─────────────────────────────────────────────────────────────

  describe "#market_news" do
    let(:news_items) { Array.new(10) { |i| { "headline" => "News #{i}" } } }

    it "returns at most count items" do
      stub_get(body: news_items)
      expect(service.market_news(count: 3).length).to eq(3)
    end

    it "returns empty array on failure" do
      stub_get(body: nil, success: false)
      expect(service.market_news).to eq([])
    end
  end
end
