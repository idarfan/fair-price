# frozen_string_literal: true

require "rails_helper"

# tasks/leaps-vertical-fix.md 通則 8：r、每口每腳費用、IV 搜尋範圍集中在 config/leaps_vertical.yml。
RSpec.describe LeapsVerticalSpreadService::Config do
  it "從 config/leaps_vertical.yml 讀出參數（BigDecimal）" do
    expect(described_class.risk_free_rate).to eq(BigDecimal("0.04"))
    expect(described_class.fee_per_contract_leg).to eq(BigDecimal("0.02"))
    expect(described_class.iv_bounds).to eq(BigDecimal("0.005")..BigDecimal("10"))
  end
end
