# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::EntryReturnCalculator do
  # 規格 S1 明訂：eps 11.02、entry 223.55／365 為測試專用值，一律以字面值
  # 寫死在本檔內，不得改由設定檔預設值提供——否則預設值一改，測試就跟著
  # 失去意義。因此下面刻意重複字面值，不抽成常數或共用變數。

  describe "定值表（eps = 11.02，容差 1e-6）" do
    subject(:result) do
      described_class.call(eps: 11.02, multiples: [ 20, 25, 33 ], entry_prices: [ 223.55, 365.0 ])
    end

    {
      20 => { target: 220.40, a: [ -0.0140908, "-1.4%" ],  b: [ -0.3961644, "-39.6%" ] },
      25 => { target: 275.50, a: [ 0.2323865,  "+23.2%" ], b: [ -0.2452055, "-24.5%" ] },
      # 規格 S1 定值表這一格寫 0.6267949，與它自己的 target 欄位（363.66）矛盾：
      # 363.66 / 223.55 - 1 = 0.6267502。0.6267949 反推出來的 entry 是 223.5439，
      # 不是 223.55。顯示值 +62.7% 兩者相同，差異只在第 5 位小數之後。
      # 這裡採用與 target 欄位一致的值。
      33 => { target: 363.66, a: [ 0.6267502,  "+62.7%" ], b: [ -0.0036712, "-0.4%" ] }
    }.each do |multiple, expected|
      context "#{multiple} 倍" do
        let(:row) { result.rows.find { |r| r.multiple == multiple } }

        it "target_price = #{expected[:target]}" do
          expect(row.target_price).to be_within(1e-6).of(expected[:target])
        end

        it "entry 223.55 → #{expected[:a][1]}" do
          cell = row.cells.first
          expect(cell.total_return).to be_within(1e-6).of(expected[:a][0])
          expect(cell.formatted_return).to eq(expected[:a][1])
        end

        it "entry 365.0 → #{expected[:b][1]}" do
          cell = row.cells.last
          expect(cell.total_return).to be_within(1e-6).of(expected[:b][0])
          expect(cell.formatted_return).to eq(expected[:b][1])
        end
      end
    end
  end

  describe "負號字元" do
    it "使用 ASCII hyphen-minus（U+002D），不得出現 U+2212" do
      formatted = PriceIn::Formatter.percent(-0.3961644)
      expect(formatted).to eq("-39.6%")
      expect(formatted).to include("-")
      expect(formatted).not_to include("−")
    end
  end

  describe ".annualized" do
    it "years 未填時回傳 nil（年化值錯得很隱蔽，寧可不顯示）" do
      expect(described_class.annualized(0.6267949, nil)).to be_nil
    end

    it "years 為 0 時回傳 nil，不拋除以零" do
      expect { described_class.annualized(0.6267949, 0) }.not_to raise_error
      expect(described_class.annualized(0.6267949, 0)).to be_nil
    end

    it "持有 2 年、總報酬 +62.7% → 年化約 +27.6%" do
      expect(described_class.annualized(0.6267949, 2)).to be_within(1e-4).of(0.2755585)
    end
  end

  describe ".discounted_target" do
    it "discounted_target(15.04, 31, 0.13, 2) ≈ 365.24（容差 0.5）" do
      expect(described_class.discounted_target(15.04, 31, 0.13, 2)).to be_within(0.5).of(365.24)
    end
  end

  describe ".implied_rate" do
    # 規格 S1 寫 0.13003，但 (466.24/365)**0.5 - 1 = 0.1302079，超出它自己給的 1e-4 容差。
    # 0.13003 是拿 discounted_target 的未捨入結果（365.16）反推來的——換句話說規格
    # 在這一格混用了捨入前與捨入後的 price_today。這裡用 365 這個明寫的輸入。
    it "implied_rate(466.24, 365, 2) ≈ 0.1302079（容差 1e-4）" do
      expect(described_class.implied_rate(466.24, 365, 2)).to be_within(1e-4).of(0.1302079)
    end

    it "與 discounted_target 互為逆運算" do
      target = described_class.discounted_target(15.04, 31, 0.13, 2)
      expect(described_class.implied_rate(15.04 * 31, target, 2)).to be_within(1e-6).of(0.13)
    end

    it "price_today 為 0 時回傳 nil，不拋例外" do
      expect { described_class.implied_rate(466.24, 0, 2) }.not_to raise_error
      expect(described_class.implied_rate(466.24, 0, 2)).to be_nil
    end
  end

  describe ".total_return" do
    it "entry_price 為 0 時回傳 nil，不拋除以零" do
      expect { described_class.total_return(220.40, 0) }.not_to raise_error
      expect(described_class.total_return(220.40, 0)).to be_nil
    end
  end
end
