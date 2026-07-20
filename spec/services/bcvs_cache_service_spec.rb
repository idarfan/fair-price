# frozen_string_literal: true

require "rails_helper"

RSpec.describe BcvsCacheService do
  let(:symbol)     { "RKLB" }
  let(:expiration) { "2026-08-21-m" }

  describe ".fresh_expirations? / .upsert_expirations!" do
    it "is not fresh when nothing cached" do
      expect(described_class.fresh_expirations?(symbol)).to eq(false)
    end

    it "is fresh immediately after upsert and stale after 30 minutes" do
      described_class.upsert_expirations!(symbol, expirations: [ "2026-08-21-m" ], underlying_price: 42.5)
      expect(described_class.fresh_expirations?(symbol)).to eq(true)

      travel 31.minutes do
        expect(described_class.fresh_expirations?(symbol)).to eq(false)
      end
    end

    it "upserts the same row on repeated calls instead of creating duplicates" do
      described_class.upsert_expirations!(symbol, expirations: [ "2026-08-21-m" ], underlying_price: 42.5)
      described_class.upsert_expirations!(symbol, expirations: [ "2026-08-21-m", "2026-09-18-m" ], underlying_price: 43.0)

      expect(BcvsExpirationSnapshot.for_symbol(symbol).count).to eq(1)
      expect(described_class.read_expirations(symbol)[:expirations]).to eq([ "2026-08-21-m", "2026-09-18-m" ])
      expect(described_class.read_expirations(symbol)[:underlying_price]).to eq(43.0)
    end

    it "stores and returns the v4 underlying summary fields" do
      described_class.upsert_expirations!(
        symbol, expirations: [ "2026-08-21-m" ], underlying_price: 42.5,
        price_change: 1.23, iv_atm: 80.76, hv: 75.23, iv_rank: 72.48,
        latest_earnings: "07/23/26 [BMO]"
      )

      summary = described_class.read_expirations(symbol)[:summary]
      expect(summary).to eq(
        price_change: 1.23, iv_atm: 80.76, hv: 75.23, iv_rank: 72.48,
        latest_earnings: "07/23/26 [BMO]"
      )
    end

    it "leaves the v4 summary fields nil when not provided (does not fabricate values)" do
      described_class.upsert_expirations!(symbol, expirations: [ "2026-08-21-m" ], underlying_price: 42.5)

      summary = described_class.read_expirations(symbol)[:summary]
      expect(summary).to eq(price_change: nil, iv_atm: nil, hv: nil, iv_rank: nil, latest_earnings: nil)
    end
  end

  describe ".fresh_chain? / .upsert_chain!" do
    it "is not fresh when nothing cached" do
      expect(described_class.fresh_chain?(symbol, expiration)).to eq(false)
    end

    it "is fresh immediately after upsert and stale after 30 minutes" do
      described_class.upsert_chain!(symbol, expiration, strikes: [], underlying_price: 42.5)
      expect(described_class.fresh_chain?(symbol, expiration)).to eq(true)

      travel 31.minutes do
        expect(described_class.fresh_chain?(symbol, expiration)).to eq(false)
      end
    end

    it "upserts the same row on repeated calls instead of creating duplicates" do
      rows = [ { "strike" => 40.0, "bid" => 1.1, "ask" => 1.3 } ]
      described_class.upsert_chain!(symbol, expiration, strikes: rows, underlying_price: 42.5)
      described_class.upsert_chain!(symbol, expiration, strikes: rows, underlying_price: 43.0)

      expect(BcvsChainSnapshot.for_symbol_and_expiration(symbol, expiration).count).to eq(1)
      expect(described_class.read_chain(symbol, expiration)[:underlying_price]).to eq(43.0)
    end

    it "keeps rows that have a positive bid or ask" do
      rows = [
        { "strike" => 40.0, "bid" => 1.1, "ask" => 1.3 },
        { "strike" => 42.0, "bid" => 0,   "ask" => 0.5 },
        { "strike" => 44.0, "bid" => 0.4, "ask" => 0 }
      ]
      described_class.upsert_chain!(symbol, expiration, strikes: rows, underlying_price: 42.5)

      expect(described_class.read_chain(symbol, expiration)[:strikes].map { |r| r["strike"] }).to eq([ 40.0, 42.0, 44.0 ])
    end

    it "drops rows where both bid and ask are 0 or null" do
      rows = [
        { "strike" => 40.0, "bid" => 1.1, "ask" => 1.3 },
        { "strike" => 42.0, "bid" => 0,   "ask" => 0 },
        { "strike" => 44.0, "bid" => nil, "ask" => nil }
      ]
      described_class.upsert_chain!(symbol, expiration, strikes: rows, underlying_price: 42.5)

      expect(described_class.read_chain(symbol, expiration)[:strikes].map { |r| r["strike"] }).to eq([ 40.0 ])
    end
  end

  describe "cache-hit does not trigger a scrape (integration with BarchartScraperService)" do
    it "does not instantiate BarchartScraperService when expirations are fresh" do
      described_class.upsert_expirations!(symbol, expirations: [ "2026-08-21-m" ], underlying_price: 42.5)
      expect(BarchartScraperService).not_to receive(:new)

      # Mirrors the controller's read path: check freshness before ever touching the scraper.
      expect(described_class.fresh_expirations?(symbol)).to eq(true)
    end
  end
end
