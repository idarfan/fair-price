# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::ShareCalculator do
  # 固定 holdings 夾具（含一筆 max=NULL），手算值：
  #   A: 1,000～3,000  → mid 2,000    B: 3,000～5,000 → mid 4,000    C: 4,000～NULL → mid = min = 4,000
  #   Σmid = 10,000 → 估算 A 20%、B 40%、C 40%
  #   Σmin =  8,000 → 下限 A 12.5%、B 37.5%、C 50%
  #   C 無上限 → 上限佔比整欄 nil，附原因
  let(:official) { create(:hof_official) }
  let(:annual)   { create(:hof_filing, official:, filing_type: "annual", year: 2025, parse_status: "parsed") }

  before do
    create(:hof_holding, filing: annual, asset_name: "A Corp (AAA)", ticker: "AAA", value_min: 1_000, value_max: 3_000)
    create(:hof_holding, filing: annual, asset_name: "B Corp (BBB)", ticker: "BBB", value_min: 3_000, value_max: 5_000)
    create(:hof_holding, filing: annual, asset_name: "C Farm [FA]",  ticker: nil,   value_min: 4_000, value_max: nil)
  end

  def shares(rows) = rows.to_h { |r| [ r[:asset_name], r.values_at(:estimated, :lower, :upper) ] }

  it "matches the hand-calculated three columns with an unbounded row (all assets)" do
    view = HallOfFame::HoldingsView.new(official).as_json[:views][:all]

    expect(shares(view[:rows])).to eq(
      "A Corp (AAA)" => [ 20.0, 12.5, nil ],
      "B Corp (BBB)" => [ 40.0, 37.5, nil ],
      "C Farm [FA]"  => [ 40.0, 50.0, nil ]
    )
    expect(view[:upper_note]).to eq(described_class::UPPER_UNAVAILABLE)
    expect(view[:rows].find { |r| r[:asset_name] == "C Farm [FA]" }[:unbounded]).to be(true)
    expect(view[:rows].sum { |r| r[:estimated] }).to be_within(0.1).of(100)
  end

  # 僅有價證券（A、B）分母重算：Σmid 6,000 → 33.3333%／66.6667%；Σmin 4,000 → 25%／75%；Σmax 8,000 → 37.5%／62.5%
  it "recomputes denominators for securities only" do
    view = HallOfFame::HoldingsView.new(official).as_json[:views][:securities]

    expect(shares(view[:rows])).to eq(
      "B Corp (BBB)" => [ 66.6667, 75.0, 62.5 ],
      "A Corp (AAA)" => [ 33.3333, 25.0, 37.5 ]
    )
    expect(view[:upper_note]).to be_nil
    expect(view[:rows].sum { |r| r[:estimated] }).to be_within(0.1).of(100)
  end

  it "returns nil shares when every amount is zero (None)" do
    result = described_class.call([ { key: 1, min: 0, max: 0 } ])

    expect(result.for(1)).to have_attributes(estimated: nil, lower: nil, upper: nil)
  end
end
