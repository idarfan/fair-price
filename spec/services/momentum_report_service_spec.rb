require "rails_helper"

RSpec.describe MomentumReportService do
  # ── Stub helpers ─────────────────────────────────────────────────────────────

  let(:fake_quote) do
    { "c" => 182.5, "d" => 1.2, "dp" => 0.66,
      "h" => 184.0, "l" => 180.0, "pc" => 181.3 }
  end

  let(:fake_chart) { { closes: [ 180.0, 182.5 ], change_pct: 0.014, volumes: [ 1_000_000, 900_000 ], timestamps: [], opens: [], highs: [], lows: [] } }

  let(:vix_double)     { instance_double(VixService, fetch: 18.5) }
  let(:finnhub_double) { instance_double(FinnhubService) }
  let(:yahoo_double)   { instance_double(YahooFinanceService) }

  before do
    allow(VixService).to receive(:new).and_return(vix_double)

    allow(FinnhubService).to receive(:new).and_return(finnhub_double)
    allow(finnhub_double).to receive(:quote).and_return(fake_quote)
    allow(finnhub_double).to receive(:earnings_calendar).and_return([])
    allow(finnhub_double).to receive(:candles).and_return(nil)

    allow(YahooFinanceService).to receive(:new).and_return(yahoo_double)
    allow(yahoo_double).to receive(:chart).and_return(fake_chart)

    allow(Rails.cache).to receive(:fetch).and_yield
  end

  describe "#call return structure" do
    subject(:result) { described_class.new(symbols: [ "AAPL" ]).call }

    it "returns a frozen hash" do
      expect(result).to be_frozen
    end

    it "includes all required keys" do
      expect(result.keys).to match_array(%i[segment et_time vix es_change nq_change stance stocks earnings])
    end

    it "returns vix from VixService" do
      expect(result[:vix]).to eq(18.5)
    end

    it "returns stocks array with one entry per symbol" do
      expect(result[:stocks].length).to eq(1)
    end

    it "returns correct stock data structure" do
      stock = result[:stocks].first
      expect(stock[:symbol]).to eq("AAPL")
      expect(stock[:price]).to be_a(Numeric)
      expect(stock[:change_pct]).to be_a(Numeric)
    end

    it "stance is nil (derived in component)" do
      expect(result[:stance]).to be_nil
    end
  end

  # ── Symbol source fallback ────────────────────────────────────────────────────

  describe "symbol source" do
    it "uses provided symbols when given" do
      result = described_class.new(symbols: [ "TSLA", "NVDA" ]).call
      expect(result[:stocks].map { |s| s[:symbol] }).to contain_exactly("TSLA", "NVDA")
    end

    it "falls back to YAML config when no symbols given and DB is empty" do
      allow(WatchlistItem).to receive(:ordered).and_raise(ActiveRecord::StatementInvalid)
      yaml_symbols = YAML.load_file(Rails.root.join("config/watchlist.yml")).fetch("symbols", [])
      result = described_class.new.call
      expect(result[:stocks].map { |s| s[:symbol] }).to match_array(yaml_symbols)
    end
  end

  # ── Error resilience ─────────────────────────────────────────────────────────

  describe "stock fetch error handling" do
    it "skips a symbol when FinnhubService returns nil" do
      allow(finnhub_double).to receive(:quote).and_return(nil)
      result = described_class.new(symbols: [ "BAD" ]).call
      expect(result[:stocks]).to be_empty
    end
  end

  describe "futures fetch error handling" do
    it "returns nil for es_change when YahooFinanceService raises" do
      # Stub only futures symbols to raise; candle calls use fake_chart from before
      allow(yahoo_double).to receive(:chart).with("ES=F", anything).and_raise(StandardError, "timeout")
      allow(yahoo_double).to receive(:chart).with("NQ=F", anything).and_raise(StandardError, "timeout")
      result = described_class.new(symbols: [ "AAPL" ]).call
      expect(result[:es_change]).to be_nil
      expect(result[:nq_change]).to be_nil
    end
  end
end
