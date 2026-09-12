# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeapsPriceContextService do
  let(:symbol) { "TSTX" }

  def create_volap(low: 94.0, high: 182.19)
    VolapSnapshot.create!(
      symbol: symbol, scraped_at: Time.current,
      period_key: VolapSnapshot::TARGET_PERIOD_KEY,
      aggregation: VolapSnapshot::TARGET_AGGREGATION,
      price_min: low, price_max: high, zone: (high - low) / 4.0, poc_index: 1,
      inputs: { "LevelSize" => 4, "Volume" => "Up/Down" },
      bars: [ { "up" => 10, "down" => 5, "is_value" => false },
              { "up" => 90, "down" => 30, "is_value" => true },
              { "up" => 40, "down" => 20, "is_value" => true },
              { "up" => 5,  "down" => 5,  "is_value" => false } ]
    )
  end

  def create_bar(date, o, h, l, c)
    DailyBar.create!(symbol: symbol, bar_date: date,
                     open_price: o, high_price: h, low_price: l, close_price: c,
                     volume: 1_000)
  end

  describe "降級路徑" do
    it "完全沒有資料時三塊都是 nil 而不是丟例外" do
      result = nil
      expect { result = described_class.new(symbol).call }.not_to raise_error

      expect(result[:poi]).to be_nil
      expect(result[:week52]).to be_nil
      expect(result[:day_range]).to be_nil
      expect(result[:current_price]).to be_nil
    end

    it "只有日線沒有 VOLAP 時，當日區間仍然畫得出來" do
      create_bar(Date.new(2026, 9, 9), 100, 102, 99, 101)
      create_bar(Date.new(2026, 9, 10), 101, 105, 100, 104)

      result = described_class.new(symbol).call

      expect(result[:poi]).to be_nil
      expect(result[:week52]).to be_nil
      expect(result[:day_range][:low]).to eq(100.0)
      expect(result[:day_range][:high]).to eq(105.0)
      expect(result[:day_range][:prev_close]).to eq(101.0)
    end
  end

  describe "52 週區間" do
    it "直接取 VOLAP 快照的價格範圍，不另外從日線算" do
      create_volap(low: 94.0, high: 182.19)
      create_bar(Date.new(2026, 9, 10), 126, 129, 124, 126.6)

      w = described_class.new(symbol).call[:week52]

      expect(w[:low]).to eq(94.0)
      expect(w[:high]).to eq(182.19)
      expect(w[:position_pct]).to eq(37.0)
    end
  end

  describe "現價落在區間外" do
    it "position_pct 回 nil 並標記 price_outside_range，不 clamp 成 0 或 100" do
      # 當日區間 10.795–10.89，但快照現價是較舊的 10.14
      create_bar(Date.new(2026, 9, 9), 10.6, 10.7, 10.5, 10.62)
      create_bar(Date.new(2026, 9, 10), 10.82, 10.89, 10.795, 10.88)
      LeapsOptionChainSnapshot.create!(
        symbol: symbol, expiration_date: Date.new(2028, 1, 21), strike: 10,
        option_type: "Call", scraped_at: Time.current, underlying_price: 10.14
      )

      d = described_class.new(symbol).call[:day_range]

      expect(d[:position_pct]).to be_nil
      expect(d[:price_outside_range]).to be(true)
      # 區間本身照常回報，只是不畫游標
      expect(d[:low]).to eq(10.795)
      expect(d[:high]).to eq(10.89)
    end

    it "現價在區間內時照常給出位置" do
      create_bar(Date.new(2026, 9, 10), 100, 110, 100, 105)
      LeapsOptionChainSnapshot.create!(
        symbol: symbol, expiration_date: Date.new(2028, 1, 21), strike: 100,
        option_type: "Call", scraped_at: Time.current, underlying_price: 105
      )

      d = described_class.new(symbol).call[:day_range]

      expect(d[:price_outside_range]).to be(false)
      expect(d[:position_pct]).to eq(50.0)
    end
  end

  describe "現價來源" do
    it "優先用 LEAPS 快照的 underlying_price（與排行表同一個數字）" do
      create_bar(Date.new(2026, 9, 10), 100, 110, 100, 105)
      LeapsOptionChainSnapshot.create!(
        symbol: symbol, expiration_date: Date.new(2028, 1, 21), strike: 100,
        option_type: "Call", scraped_at: Time.current, underlying_price: 108.5
      )

      expect(described_class.new(symbol).call[:current_price]).to eq(108.5)
    end

    it "沒有 LEAPS 快照時退回最新一根日線的收盤" do
      create_bar(Date.new(2026, 9, 10), 100, 110, 100, 105)

      expect(described_class.new(symbol).call[:current_price]).to eq(105.0)
    end
  end

  describe "高低相等的區間" do
    it "high == low 時回 nil，不除以零" do
      create_bar(Date.new(2026, 9, 10), 50, 50, 50, 50)

      expect(described_class.new(symbol).call[:day_range]).to be_nil
    end
  end
end
