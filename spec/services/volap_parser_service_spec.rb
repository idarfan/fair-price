# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolapParserService do
  # 10 箱、每箱寬 1.0、範圍 100–110，方便手算。
  def snapshot(totals, value_flags: nil, poc_index: nil)
    poc = poc_index || totals.index(totals.max)
    VolapSnapshot.new(
      symbol: "TEST", scraped_at: Time.current,
      period_key: VolapSnapshot::TARGET_PERIOD_KEY,
      aggregation: VolapSnapshot::TARGET_AGGREGATION,
      price_min: 100, price_max: 110, zone: 1.0, poc_index: poc, inputs: {},
      bars: totals.each_with_index.map do |t, i|
        { "up" => t, "down" => 0,
          "is_value" => value_flags.nil? ? true : value_flags[i] }
      end
    )
  end

  describe "#bins" do
    it "把 POC 標在 snapshot 指定的箱上，不自己重算" do
      # 故意讓 poc_index 指向「不是最大量」的箱：POC 是 Barchart 算的，
      # 這支服務不得覆寫它的判斷。
      parser = described_class.new(snapshot([ 10, 100, 50 ], poc_index: 2))

      expect(parser.poc_bin.index).to eq(2)
      expect(parser.bins.count(&:is_poc)).to eq(1)
    end

    it "pct_of_max 以最大量的箱為 100%" do
      bins = described_class.new(snapshot([ 25, 100, 50 ])).bins

      expect(bins.map(&:pct_of_max)).to eq([ 25.0, 100.0, 50.0 ])
    end

    it "箱的價格區間由 price_min 與 zone 推出" do
      bin = described_class.new(snapshot([ 1, 2, 3 ])).bins[1]

      expect(bin.low).to eq(101.0)
      expect(bin.high).to eq(102.0)
      expect(bin.mid).to eq(101.5)
    end

    it "整段沒有成交量時回空陣列，不除以零" do
      expect { described_class.new(snapshot([ 0, 0, 0 ])).bins }.not_to raise_error
      expect(described_class.new(snapshot([ 0, 0, 0 ])).bins).to eq([])
    end

    it "bars 為空或 snapshot 為 nil 時回空陣列" do
      empty = snapshot([])
      empty.bars = []
      expect(described_class.new(empty).bins).to eq([])
      expect(described_class.new(nil).bins).to eq([])
    end
  end

  describe "HVN / LVN" do
    it "POC 本身不重複標成 HVN" do
      parser = described_class.new(snapshot([ 10, 100, 90 ]))

      expect(parser.poc_bin.is_hvn).to be(false)
      expect(parser.bins[2].is_hvn).to be(true)   # 90% ≥ 55%
    end

    it "相鄰的 HVN 合併成一段價區" do
      parser = described_class.new(snapshot([ 10, 100, 80, 75, 10 ]))

      zones = parser.merged_zones(:hvn)
      expect(zones.size).to eq(1)
      expect(zones.first[:bins]).to eq([ 2, 3 ])
      expect(zones.first[:low]).to eq(102.0)
      expect(zones.first[:high]).to eq(104.0)
    end

    it "不相鄰的 HVN 分成兩段" do
      parser = described_class.new(snapshot([ 80, 10, 100, 10, 75 ]))

      expect(parser.merged_zones(:hvn).map { |z| z[:bins] }).to eq([ [ 0 ], [ 4 ] ])
    end

    it "Value Area 之外的低量箱不算 LVN（那是價格很少走到，不是沒人接）" do
      # 箱 0 與箱 4 都是 5%，但只有箱 0 在 Value Area 內
      parser = described_class.new(
        snapshot([ 5, 100, 60, 60, 5 ], value_flags: [ true, true, true, true, false ])
      )

      expect(parser.bins[0].is_lvn).to be(true)
      expect(parser.bins[4].is_lvn).to be(false)
    end
  end

  describe "#value_area" do
    it "取所有 isValue 箱的最外緣" do
      parser = described_class.new(
        snapshot([ 10, 50, 100, 50, 10 ], value_flags: [ false, true, true, true, false ])
      )

      expect(parser.value_area).to eq({ low: 101.0, high: 104.0 })
    end

    it "沒有任何 isValue 箱時回 nil" do
      parser = described_class.new(snapshot([ 10, 100 ], value_flags: [ false, false ]))

      expect(parser.value_area).to be_nil
    end
  end
end
