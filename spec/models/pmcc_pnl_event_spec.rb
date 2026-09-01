# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccPnlEvent do
  it "只接受已定義的事件類型" do
    PmccPnlEvent::EVENT_TYPES.each do |t|
      expect(build(:pmcc_pnl_event, event_type: t)).to be_valid
    end
    expect(build(:pmcc_pnl_event, event_type: "short_rolled")).not_to be_valid
  end

  it "已實現損益可以是負數（買回成本高於收租）" do
    expect(build(:pmcc_pnl_event, realized_pnl: -120.5)).to be_valid
  end

  it "手續費不能是負數" do
    expect(build(:pmcc_pnl_event, fees: -1)).not_to be_valid
  end

  # pmcc_leg_quotes 是覆蓋式快照，事後查不到當時的報價，
  # 要能回溯就必須在建立事件時留存
  it "可留存當下用到的報價" do
    event = create(:pmcc_pnl_event, quote_snapshot: { "mid" => 129.7, "delta" => 0.8978 })

    expect(event.reload.quote_snapshot["mid"]).to eq(129.7)
  end

  it "chronological 依發生時間排序" do
    later   = create(:pmcc_pnl_event, occurred_at: 1.day.ago)
    earlier = create(:pmcc_pnl_event, occurred_at: 3.days.ago)

    expect(described_class.chronological.first).to eq(earlier)
    expect(described_class.chronological.last).to eq(later)
  end
end
