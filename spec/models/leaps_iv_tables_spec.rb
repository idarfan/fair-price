# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment.md P1：三張表的必填欄位與「upsert，後寫覆蓋先寫」的唯一鍵。
RSpec.describe "LEAPS IV 環境資料表", type: :model do
  let(:now) { Time.current }

  describe LeapsIvSnapshot do
    let(:attrs) do
      { symbol: "TSM", as_of_date: Date.new(2026, 11, 5), source: "adhoc", captured_at: now,
        source_url: "https://www.barchart.com/stocks/quotes/TSM/options" }
    end

    it "必填欄位齊全時有效" do
      expect(described_class.new(attrs)).to be_valid
    end

    it "source 只接受 scheduled／adhoc" do
      expect(described_class.new(attrs.merge(source: "manual"))).not_to be_valid
      expect(described_class.new(attrs.merge(source: "scheduled"))).to be_valid
    end

    it "缺 as_of_date、captured_at、source_url 時無效" do
      %i[as_of_date captured_at source_url].each do |key|
        expect(described_class.new(attrs.except(key))).not_to be_valid, "缺 #{key} 應無效"
      end
    end

    it "同一 symbol＋as_of_date upsert 時，後寫覆蓋先寫（盤中 adhoc 被收盤後 scheduled 取代）" do
      described_class.upsert(attrs.merge(spot: 360.55), unique_by: %i[symbol as_of_date])
      described_class.upsert(attrs.merge(spot: 353.10, source: "scheduled"), unique_by: %i[symbol as_of_date])

      rows = described_class.where(symbol: "TSM", as_of_date: Date.new(2026, 11, 5))
      expect(rows.count).to eq(1)
      expect(rows.first).to have_attributes(spot: BigDecimal("353.1"), source: "scheduled")
    end
  end

  describe LeapsIvSurfacePoint do
    let(:attrs) do
      { symbol: "TSM", as_of_date: Date.new(2026, 11, 5), expiration: Date.new(2028, 1, 21),
        strike: 350, dte: 442, moneyness: 0.9912, call_iv: 0.4246, delta: 0.6258, captured_at: now }
    end

    it "必填欄位齊全時有效，缺到期日或履約價時無效" do
      expect(described_class.new(attrs)).to be_valid
      expect(described_class.new(attrs.except(:expiration))).not_to be_valid
      expect(described_class.new(attrs.except(:strike))).not_to be_valid
    end

    it "同一 symbol＋as_of_date＋到期日＋履約價 upsert 只留一列，值以後寫為準" do
      key = %i[symbol as_of_date expiration strike]
      described_class.upsert(attrs, unique_by: key)
      described_class.upsert(attrs.merge(call_iv: 0.4300), unique_by: key)

      expect(described_class.where(attrs.slice(*key)).pluck(:call_iv)).to eq([ BigDecimal("0.43") ])
    end
  end

  describe BarchartIvHistory do
    let(:attrs) do
      { symbol: "TSM", trade_date: Date.new(2026, 11, 5), imp_vol: 0.5192, iv_rank: 82.44, iv_pctl: 92.43,
        pc_vol_ratio: 0.9182, options_volume: 418_426, pc_oi_ratio: 0.9812, total_oi: 1_921_298,
        last_price: 353.10, captured_at: now,
        source_url: "https://www.barchart.com/stocks/quotes/TSM/options-history" }
    end

    it "必填欄位齊全時有效，缺 trade_date 或 source_url 時無效" do
      expect(described_class.new(attrs)).to be_valid
      expect(described_class.new(attrs.except(:trade_date))).not_to be_valid
      expect(described_class.new(attrs.except(:source_url))).not_to be_valid
    end

    it "IV Rank／Pctl 以 0–100 存兩位小數，IV 以小數存五位" do
      row = described_class.create!(attrs)
      expect(row.reload).to have_attributes(iv_rank: BigDecimal("82.44"), iv_pctl: BigDecimal("92.43"),
                                            imp_vol: BigDecimal("0.5192"))
    end

    it "同一 symbol＋trade_date upsert 只留一列" do
      described_class.upsert(attrs, unique_by: %i[symbol trade_date])
      described_class.upsert(attrs.merge(iv_rank: 80.00), unique_by: %i[symbol trade_date])

      expect(described_class.where(symbol: "TSM", trade_date: Date.new(2026, 11, 5)).pluck(:iv_rank))
        .to eq([ BigDecimal("80") ])
    end
  end
end
