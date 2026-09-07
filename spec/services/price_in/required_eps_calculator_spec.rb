# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::RequiredEpsCalculator do
  # 規格 S1 定值表，容差 1e-6
  describe "反推所需 EPS（price = 223.55）" do
    subject(:calc) { described_class.new(price: 223.55, multiples: [ 25, 30, 35 ]) }

    {
      25 => 8.942000,
      30 => 7.451667,
      35 => 6.387143
    }.each do |multiple, expected|
      it "#{multiple} 倍 → #{expected}" do
        expect(calc.required_eps(multiple)).to be_within(1e-6).of(expected)
      end
    end

    {
      25 => "$8.94",
      30 => "$7.45",
      35 => "$6.39"
    }.each do |multiple, expected|
      it "#{multiple} 倍顯示為 #{expected}" do
        row = calc.call.rows.find { |r| r.multiple == multiple }
        expect(row.formatted_eps).to eq(expected)
      end
    end
  end

  describe "邊界" do
    subject(:calc) { described_class.new(price: 223.55, multiples: [ 25 ]) }

    it "multiple 為 0 時回傳 nil，不拋例外" do
      expect { calc.required_eps(0) }.not_to raise_error
      expect(calc.required_eps(0)).to be_nil
    end

    it "multiple 為 nil 時回傳 nil，不拋例外" do
      expect(calc.required_eps(nil)).to be_nil
    end
  end

  describe ".implied_multiple（price = 223.55）" do
    {
      6.60  => [ 33.8712, "33.9 倍" ],
      7.24  => [ 30.8771, "30.9 倍" ],
      11.02 => [ 20.2859, "20.3 倍" ]
    }.each do |eps, (value, display)|
      it "eps #{eps} → #{display}" do
        result = described_class.implied_multiple(223.55, eps)
        expect(result).to be_within(1e-4).of(value)
        expect(PriceIn::Formatter.multiple(result)).to eq(display)
      end
    end

    it "eps 為 0 回傳 nil，顯示為破折號" do
      expect(described_class.implied_multiple(223.55, 0)).to be_nil
      expect(PriceIn::Formatter.multiple(nil)).to eq("—")
    end

    it "eps 為 nil 回傳 nil，不拋例外" do
      expect { described_class.implied_multiple(223.55, nil) }.not_to raise_error
      expect(described_class.implied_multiple(223.55, nil)).to be_nil
    end
  end

  describe "色帶" do
    it "低高皆有值時 band? 為 true" do
      result = described_class.call(price: 223.55, multiples: [ 30 ], band_low: 6.6, band_high: 7.24)
      expect(result).to be_band
    end

    it "缺一邊時 band? 為 false" do
      result = described_class.call(price: 223.55, multiples: [ 30 ], band_low: 6.6)
      expect(result).not_to be_band
    end
  end
end
