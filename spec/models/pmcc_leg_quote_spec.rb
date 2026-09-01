# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccLegQuote do
  it "symbol 一律轉大寫" do
    expect(create(:pmcc_leg_quote, symbol: "be").symbol).to eq("BE")
  end

  it "for_leg 依 symbol + 到期日 + 履約價取回報價" do
    create(:pmcc_leg_quote, symbol: "BE", strike: 100)

    expect(described_class.for_leg("be", Date.new(2028, 1, 21), 100).mid).to eq(129.7)
    expect(described_class.for_leg("BE", Date.new(2028, 1, 21), 105)).to be_nil
  end

  # 覆蓋式快照：同一腳只會有一列，重抓要更新不是新增
  it "同一腳不允許重複列" do
    create(:pmcc_leg_quote)

    expect { create(:pmcc_leg_quote) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
