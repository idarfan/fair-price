# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::BlackScholes do
  # 手算基準（Hull 例題 S=42、K=40、r=0.1、σ=0.2、T=0.5）：call 4.76、put 0.81。
  it "prices calls and puts" do
    expect(described_class.price(s: 42.0, k: 40.0, t: 0.5, r: 0.1, sigma: 0.2, right: "call")).to be_within(0.005).of(4.76)
    expect(described_class.price(s: 42.0, k: 40.0, t: 0.5, r: 0.1, sigma: 0.2, right: "put")).to be_within(0.005).of(0.81)
  end

  it "computes annualized historical volatility from closes" do
    # 報酬 ln(1.1)、ln(1/1.1) 交替：樣本標準差 = |ln 1.1| × √(4/3)
    closes = [ 100.0, 110.0, 100.0, 110.0, 100.0 ]
    expected = Math.log(1.1) * Math.sqrt(4.0 / 3) * Math.sqrt(252)

    expect(described_class.historical_volatility(closes)).to be_within(1e-9).of(expected)
  end

  it "rejects non-positive time or volatility" do
    expect { described_class.price(s: 1.0, k: 1.0, t: 0, r: 0.04, sigma: 0.2, right: "call") }.to raise_error(ArgumentError)
  end
end
