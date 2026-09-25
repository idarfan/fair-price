# frozen_string_literal: true

require "rails_helper"

# LEAPS 垂直價差專用快取（與 bcvs 分開）。chain 存 leaps_spread_quotes（每檔履約價一列、
# decimal 欄位）；到期日清單存 Rails.cache，以 scraped_at 判斷 30 分鐘。
RSpec.describe LeapsSpreadCache do
  let(:symbol)     { "ORCL" }
  let(:expiration) { "2027-10-15-m" }
  let(:rows) do
    [
      { "strike" => BigDecimal("230"), "bid" => BigDecimal("0"), "ask" => BigDecimal("0"),
        "last" => BigDecimal("11.2"), "delta" => nil },
      { "strike" => 100, "bid" => BigDecimal("40.1"), "ask" => BigDecimal("41.3"),
        "last" => BigDecimal("40.5"), "delta" => BigDecimal("0.82") }
    ]
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  describe "chain" do
    it "沒有快取時 read_chain 回 nil、fresh_chain? 為 false" do
      expect(described_class.read_chain(symbol, expiration)).to be_nil
      expect(described_class.fresh_chain?(symbol, expiration)).to be(false)
    end

    it "寫入後 30 分鐘內 fresh，31 分鐘後過期" do
      described_class.replace_chain!(symbol, expiration, rows: rows, underlying_price: BigDecimal("139.54"))
      expect(described_class.fresh_chain?(symbol, expiration)).to be(true)
      travel(31.minutes) { expect(described_class.fresh_chain?(symbol, expiration)).to be(false) }
    end

    it "存全部列（含 bid、ask 皆 0），依履約價排序，數值為 BigDecimal" do
      described_class.replace_chain!(symbol, expiration, rows: rows, underlying_price: BigDecimal("139.54"))
      chain = described_class.read_chain(symbol, expiration)

      expect(chain[:strikes].map { |r| r[:strike] }).to eq([ BigDecimal("100"), BigDecimal("230") ])
      expect(chain[:strikes].last).to include(bid: BigDecimal("0"), ask: BigDecimal("0"),
                                              last: BigDecimal("11.2"), delta: nil)
      numeric = chain[:strikes].flat_map { |r| r.values_at(:strike, :bid, :ask, :last, :delta) }.compact
      expect(numeric).to all(be_a(BigDecimal))
      expect(chain[:underlying_price]).to eq(BigDecimal("139.54"))
    end

    it "重抓時整批取代，不留下舊的履約價" do
      described_class.replace_chain!(symbol, expiration, rows: rows, underlying_price: BigDecimal("139.54"))
      described_class.replace_chain!(symbol, expiration, rows: [ rows.last ], underlying_price: BigDecimal("140"))

      chain = described_class.read_chain(symbol, expiration)
      expect(chain[:strikes].map { |r| r[:strike] }).to eq([ BigDecimal("100") ])
      expect(LeapsSpreadQuote.where(symbol: symbol, expiration: expiration).count).to eq(1)
    end

    it "不影響其他到期日與 bcvs 的表" do
      described_class.replace_chain!(symbol, "2028-01-21-m", rows: rows, underlying_price: BigDecimal("139.54"))
      described_class.replace_chain!(symbol, expiration, rows: [ rows.last ], underlying_price: BigDecimal("139.54"))

      expect(LeapsSpreadQuote.where(symbol: symbol, expiration: "2028-01-21-m").count).to eq(2)
      expect(BcvsChainSnapshot.where(symbol: symbol)).not_to exist
    end
  end

  describe "到期日清單（Rails.cache）" do
    let(:list) { [ "2026-11-20-m", expiration ] }

    it "寫入後 30 分鐘內 fresh；過期後仍讀得到（選單切換時沿用舊清單）" do
      described_class.write_expirations!(symbol, list)
      expect(described_class.fresh_expirations?(symbol)).to be(true)

      travel(31.minutes) do
        expect(described_class.fresh_expirations?(symbol)).to be(false)
        expect(described_class.read_expirations(symbol)).to eq(list)
      end
    end

    it "沒有快取時回 nil" do
      expect(described_class.read_expirations(symbol)).to be_nil
      expect(described_class.fresh_expirations?(symbol)).to be(false)
    end
  end
end
