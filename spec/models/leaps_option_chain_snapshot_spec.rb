# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeapsOptionChainSnapshot, type: :model do
  # fresh window 邊界測試（spec「fresh window 5 → 30 分鐘」節）：
  # 用 FRESH_WINDOW ± 1.minute 表達邊界，不寫死 29/31 分鐘字面值。
  describe ".fresh scope boundary" do
    let(:base_attrs) do
      {
        symbol: "FWTEST", expiration_date: Date.new(2028, 1, 21),
        strike: 10.0, option_type: "Call"
      }
    end

    after { described_class.where(symbol: "FWTEST").delete_all }

    it "FRESH_WINDOW is 30 minutes (single source of truth)" do
      expect(described_class::FRESH_WINDOW).to eq(30.minutes)
    end

    it "includes rows scraped just inside the window" do
      travel_to Time.current do
        described_class.create!(
          base_attrs.merge(scraped_at: (described_class::FRESH_WINDOW - 1.minute).ago)
        )
        expect(described_class.for_symbol("FWTEST").fresh.exists?).to be true
      end
    end

    it "excludes rows scraped just outside the window" do
      travel_to Time.current do
        described_class.create!(
          base_attrs.merge(scraped_at: (described_class::FRESH_WINDOW + 1.minute).ago)
        )
        expect(described_class.for_symbol("FWTEST").fresh.exists?).to be false
      end
    end
  end
  # Phase H：內在/外在價值公式（唯一定義處）的單元測試。
  # PMCC v3 §2.1 改版：derived_values 改接收呼叫端決定好的 mid，不再自己從 bid/ask 重算；
  # 這裡的 mid 一律用 (bid+ask)/2 模擬 LEAPS 呼叫端行為（改版前後數值必須一致）。
  describe ".derived_values" do
    it "deep ITM call: intrinsic > 0, extrinsic = mid - intrinsic" do
      d = described_class.derived_values(
        option_type: "Call", strike: 7.0, underlying_price: 12.07, mid: (4.7 + 5.65) / 2.0
      )
      expect(d[:intrinsic_value]).to be_within(0.0001).of(5.07)
      expect(d[:extrinsic_value]).to be_within(0.0001).of(0.105)
    end

    it "OTM call: intrinsic = 0, extrinsic = full mid" do
      d = described_class.derived_values(
        option_type: "Call", strike: 15.0, underlying_price: 12.0, mid: (0.4 + 0.6) / 2.0
      )
      expect(d[:intrinsic_value]).to eq(0.0)
      expect(d[:extrinsic_value]).to be_within(0.0001).of(0.5)
    end

    it "returns both nil when mid is nil (e.g. bid or ask missing upstream, not 0)" do
      d = described_class.derived_values(
        option_type: "Call", strike: 10.0, underlying_price: 12.0, mid: nil
      )
      expect(d).to eq(intrinsic_value: nil, extrinsic_value: nil)
    end

    it "returns both nil when underlying_price is nil" do
      d = described_class.derived_values(
        option_type: "Call", strike: 10.0, underlying_price: nil, mid: (2.8 + 3.0) / 2.0
      )
      expect(d).to eq(intrinsic_value: nil, extrinsic_value: nil)
    end

    # 表結構保留 put 是為了未來 PMCC 共用；公式分支在此釘住，
    # 防止未來 PMCC 接上時才發現寫死 call。
    it "put branch: intrinsic = max(0, strike - spot)" do
      d = described_class.derived_values(
        option_type: "Put", strike: 15.0, underlying_price: 10.0, mid: (5.2 + 5.6) / 2.0
      )
      expect(d[:intrinsic_value]).to be_within(0.0001).of(5.0)
      expect(d[:extrinsic_value]).to be_within(0.0001).of(0.4)
    end

    it "OTM put: intrinsic = 0" do
      d = described_class.derived_values(
        option_type: "Put", strike: 8.0, underlying_price: 10.0, mid: (0.3 + 0.5) / 2.0
      )
      expect(d[:intrinsic_value]).to eq(0.0)
      expect(d[:extrinsic_value]).to be_within(0.0001).of(0.4)
    end
  end

  # PMCC v3 §11 mid 一致性測試：mid 由呼叫端決定，derived_values 不得自行從 bid/ask 重算，
  # 用一組 mid ≠ (bid+ask)/2 的資料證明 extrinsic_value 確實是用傳入的 mid 算，不是重算出來的。
  describe ".derived_values — mid 一致性（不得自行從 bid/ask 重算）" do
    it "uses the passed-in mid verbatim even when it differs from (bid+ask)/2" do
      # OTM call（intrinsic=0）：bid=0.23 ask=0.26 → (bid+ask)/2=0.245，
      # 但這裡故意傳入 Barchart 原始 midpoint 0.24，extrinsic 應直接等於傳入值
      d = described_class.derived_values(
        option_type: "Call", strike: 15.0, underlying_price: 10.5, mid: 0.24
      )
      expect(d[:intrinsic_value]).to eq(0.0)
      expect(d[:extrinsic_value]).to be_within(0.0001).of(0.24)
      expect(d[:extrinsic_value]).not_to be_within(0.0001).of(0.245)
    end
  end

  # fixture 層人工對照（規格 Phase H）：2026-07-02 NVTS 快照數值釘公式。
  # 這組數字是歷史快照，只用於此測試——不得拿 live 抓取輸出來對這組數字
  # （live 的 spot/bid/ask 早已變動，live 層對照見 E2E 驗收）。
  # PMCC v3 §0/§13 Step0 回歸：derived_values 改接口後，這組 fixture 數值必須完全不變。
  describe ".derived_values — NVTS 2026-07-02 fixture（釘公式，PMCC v3 Step0 回歸）" do
    SPOT_20260702 = 14.46

    it "strike 5（bid 10.70/ask 11.30 → Mid 11.00）→ 內在 9.46、外在 1.54、佔比 14%" do
      mid = (10.70 + 11.30) / 2.0
      d = described_class.derived_values(
        option_type: "Call", strike: 5.0, underlying_price: SPOT_20260702, mid: mid
      )
      expect(d[:intrinsic_value]).to be_within(0.005).of(9.46)
      expect(d[:extrinsic_value]).to be_within(0.005).of(1.54)
      expect(d[:extrinsic_value] / mid).to be_within(0.005).of(0.14)
    end

    it "strike 10（bid 8.70/ask 9.95 → Mid 9.325）→ 內在 4.46、外在 4.87、佔比 52%" do
      mid = (8.70 + 9.95) / 2.0
      d = described_class.derived_values(
        option_type: "Call", strike: 10.0, underlying_price: SPOT_20260702, mid: mid
      )
      expect(d[:intrinsic_value]).to be_within(0.005).of(4.46)
      expect(d[:extrinsic_value]).to be_within(0.005).of(4.865)
      expect(d[:extrinsic_value] / mid).to be_within(0.005).of(0.52)
    end
  end
end
