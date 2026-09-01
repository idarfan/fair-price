# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccShortLeg do
  it "口數必須是正整數" do
    expect(build(:pmcc_short_leg, contracts: 0)).not_to be_valid
  end

  it "買回成本可以是 nil（尚未平倉）或 0（到期歸零），但不能是負數" do
    expect(build(:pmcc_short_leg, close_cost: nil)).to be_valid
    expect(build(:pmcc_short_leg, close_cost: 0)).to be_valid
    expect(build(:pmcc_short_leg, close_cost: -1)).not_to be_valid
  end

  it "拒絕非法 status" do
    expect(build(:pmcc_short_leg, status: "rolled_over")).not_to be_valid
    PmccShortLeg::VALID_STATUSES.each do |s|
      expect(build(:pmcc_short_leg, status: s)).to be_valid
    end
  end

  it "收租總額 = 每股 × 100 × 口數" do
    leg = build(:pmcc_short_leg, contracts: 2, premium_collected: 3.2)

    expect(leg.premium_total).to eq(640)
  end

  it "未填買回成本時總額算 0（到期歸零的情形）" do
    expect(build(:pmcc_short_leg, contracts: 2, close_cost: nil).close_cost_total).to eq(0)
  end
end
