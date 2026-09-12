# frozen_string_literal: true

require "rails_helper"

# 結構型 POI 的四條規則沒有業界統一定義，所以每一條都要有「這樣就算／這樣就不算」
# 的成對測試把規則釘死，否則日後誰調一個常數都沒人知道行為變了。
RSpec.describe StructuralPoiService do
  # 不落 DB：這支 service 只讀 bar 的屬性，用 Struct 當替身比建 264 筆記錄快得多，
  # 也讓每個案例的資料一眼看得完。
  Bar = Struct.new(:bar_date, :open_price, :high_price, :low_price, :close_price, :volume)

  # 平靜的墊底行情：把 ATR 撐起來，好讓後面刻意安排的位移根真的超過門檻。
  # 每根全距 1.0，所以 ATR ≈ 1.0，位移門檻 ≈ 1.5。
  def calm_bars(count, start_date: Date.new(2026, 1, 1), price: 100.0)
    (0...count).map do |i|
      Bar.new(start_date + i, price, price + 0.5, price - 0.5, price, 1_000)
    end
  end

  describe "#fvgs" do
    it "三根之間留下未回補的向上缺口時認定為看漲 FVG" do
      bars = calm_bars(3)
      bars[0] = Bar.new(bars[0].bar_date, 100, 101, 99, 100, 1)
      bars[1] = Bar.new(bars[1].bar_date, 101, 106, 101, 105, 1)
      bars[2] = Bar.new(bars[2].bar_date, 105, 108, 103, 107, 1)

      fvg = described_class.new(bars).fvgs.first

      expect(fvg.kind).to eq(:fvg)
      expect(fvg.direction).to eq(:bullish)
      expect(fvg.low).to eq(101.0)   # bar1.high
      expect(fvg.high).to eq(103.0)  # bar3.low
    end

    it "第一根與第三根有重疊時不算 FVG" do
      bars = calm_bars(3)
      bars[0] = Bar.new(bars[0].bar_date, 100, 104, 99, 103, 1)
      bars[2] = Bar.new(bars[2].bar_date, 103, 108, 103, 107, 1)

      expect(described_class.new(bars).fvgs).to be_empty
    end

    it "向下缺口認定為看跌 FVG，區間取 bar3.high 到 bar1.low" do
      bars = calm_bars(3)
      bars[0] = Bar.new(bars[0].bar_date, 100, 101, 99, 100, 1)
      bars[1] = Bar.new(bars[1].bar_date, 99, 99, 94, 95, 1)
      bars[2] = Bar.new(bars[2].bar_date, 95, 97, 93, 94, 1)

      fvg = described_class.new(bars).fvgs.first

      expect(fvg.direction).to eq(:bearish)
      expect(fvg.low).to eq(97.0)
      expect(fvg.high).to eq(99.0)
    end
  end

  describe "#gaps" do
    it "開盤跳空高於前收時認定為看漲缺口" do
      bars = calm_bars(2)
      bars[0] = Bar.new(bars[0].bar_date, 100, 101, 99, 100, 1)
      bars[1] = Bar.new(bars[1].bar_date, 104, 106, 104, 105, 1)

      gap = described_class.new(bars).gaps.first

      expect(gap.kind).to eq(:gap)
      expect(gap.direction).to eq(:bullish)
      expect(gap.low).to eq(100.0)
      expect(gap.high).to eq(104.0)
    end

    it "開盤等於前收時沒有缺口" do
      bars = calm_bars(2)
      bars[0] = Bar.new(bars[0].bar_date, 100, 101, 99, 100, 1)
      bars[1] = Bar.new(bars[1].bar_date, 100, 102, 99, 101, 1)

      expect(described_class.new(bars).gaps).to be_empty
    end
  end

  describe "#order_blocks" do
    it "取位移根之前最後一根反向 K 的實體" do
      bars = calm_bars(20)
      # index 18 是最後一根黑K（實體 100 → 99）
      bars[18] = Bar.new(bars[18].bar_date, 100, 100.5, 98.5, 99, 1)
      # index 19 是多頭位移根：實體 4.0 遠大於 ATR(≈1) × 1.5
      bars[19] = Bar.new(bars[19].bar_date, 99, 103.5, 99, 103, 1)

      ob = described_class.new(bars).order_blocks.first

      expect(ob.kind).to eq(:order_block)
      expect(ob.direction).to eq(:bullish)
      expect(ob.low).to eq(99.0)    # 實體下緣（收）
      expect(ob.high).to eq(100.0)  # 實體上緣（開）
      expect(ob.formed_on).to eq(bars[18].bar_date)
    end

    it "沒有任何一根達到位移門檻時不產生 Order Block" do
      expect(described_class.new(calm_bars(20)).order_blocks).to be_empty
    end
  end

  describe "#supply_demand_zones" do
    it "位移根之前的窄幅盤整認定為需求區" do
      bars = calm_bars(20)
      bars[19] = Bar.new(bars[19].bar_date, 100, 104.5, 100, 104, 1)

      zone = described_class.new(bars).supply_demand_zones.first

      expect(zone.kind).to eq(:demand)
      expect(zone.low).to eq(99.5)
      expect(zone.high).to eq(100.5)
    end
  end

  describe "#call" do
    it "已經被回補一半以上的結構不列入" do
      bars = calm_bars(3)
      bars[0] = Bar.new(bars[0].bar_date, 100, 101, 99, 100, 1)
      bars[1] = Bar.new(bars[1].bar_date, 101, 106, 101, 105, 1)
      bars[2] = Bar.new(bars[2].bar_date, 105, 108, 103, 107, 1)
      # 之後價格整根跌回缺口下方 → 完全回補
      filled = bars + [ Bar.new(Date.new(2026, 1, 10), 103, 103, 100, 100.5, 1) ]

      svc = described_class.new(filled)
      expect(svc.fvgs).not_to be_empty          # 規則本身仍然認得它
      expect(svc.call.select { |p| p.kind == :fvg }).to be_empty  # 但已失效不輸出
    end

    it "K 棒不足以算出 ATR 時回空陣列而不是丟例外" do
      expect { described_class.new(calm_bars(3)).call }.not_to raise_error
      expect(described_class.new(calm_bars(3)).call).to eq([])
      expect(described_class.new([]).call).to eq([])
      expect(described_class.new(nil).call).to eq([])
    end

    it "輸出依價位由低到高排序" do
      bars = calm_bars(30)
      bars[29] = Bar.new(bars[29].bar_date, 100, 104.5, 100, 104, 1)
      lows = described_class.new(bars).call.map(&:low)
      expect(lows).to eq(lows.sort)
    end

    it "由新到舊傳入時結果與由舊到新相同（入口會自己排序）" do
      bars = calm_bars(30)
      bars[29] = Bar.new(bars[29].bar_date, 100, 104.5, 100, 104, 1)

      forward = described_class.new(bars).call
      reversed = described_class.new(bars.reverse).call

      expect(reversed).to eq(forward)
    end
  end
end
