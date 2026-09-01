# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccPosition do
  it "ticker 一律轉大寫去空白" do
    expect(create(:pmcc_position, ticker: " be ").ticker).to eq("BE")
  end

  it "口數必須是正整數" do
    expect(build(:pmcc_position, long_contracts: 0)).not_to be_valid
    expect(build(:pmcc_position, long_contracts: 2)).to be_valid
  end

  it "拒絕非法 status" do
    expect(build(:pmcc_position, status: "half_closed")).not_to be_valid
  end

  describe "per-user 隔離" do
    # 真正的風險不是「被看到」而是「被寫入」：Phase 5 的表單若不 scope，
    # 其他帳號能改你的持倉、寫進你的帳本，而且事後查不出是誰做的。
    it "必須綁定 user" do
      expect(build(:pmcc_position, user: nil)).not_to be_valid
    end

    it "從 current_user 出發查不到別人的部位（RecordNotFound，不是查得到但不能改）" do
      mine     = create(:pmcc_position)
      other    = create(:pmcc_position, user: create(:user))

      expect(mine.user.pmcc_positions.find(mine.id)).to eq(mine)
      expect { mine.user.pmcc_positions.find(other.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "刪除使用者會一併清掉他的部位" do
      position = create(:pmcc_position)

      expect { position.user.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe "關聯" do
    let(:position) { create(:pmcc_position) }

    it "同時只認一筆 open 短腳" do
      create(:pmcc_short_leg, position: position, short_strike: 230, status: "rolled", close_cost: 1.1)
      open_leg = create(:pmcc_short_leg, position: position, short_strike: 240)

      expect(position.open_short_leg).to eq(open_leg)
    end

    it "roll 鏈可雙向查詢" do
      old_leg = create(:pmcc_short_leg, position: position, status: "rolled", close_cost: 1.1)
      new_leg = create(:pmcc_short_leg, position: position, short_strike: 240)
      old_leg.update!(rolled_to: new_leg)

      expect(old_leg.reload.rolled_to).to eq(new_leg)
      expect(new_leg.reload.rolled_from).to eq(old_leg)
    end

    it "刪除部位會一併清掉短腳與帳本" do
      create(:pmcc_short_leg, position: position)
      create(:pmcc_pnl_event, position: position)

      expect { position.destroy! }
        .to change(PmccShortLeg, :count).by(-1)
        .and change(PmccPnlEvent, :count).by(-1)
    end
  end

  describe "金額換算" do
    let(:position) { create(:pmcc_position, long_contracts: 2, long_entry_cost: 120.5) }

    it "長腳成本 = 每股 × 100 × 口數" do
      expect(position.long_cost_basis).to eq(24_100)
    end

    it "累積已實現只加總帳本，不含估算" do
      create(:pmcc_pnl_event, position: position, realized_pnl: 417.4)
      create(:pmcc_pnl_event, position: position, realized_pnl: -50)

      expect(position.realized_pnl).to eq(367.4)
    end

    # 滾倉收租會持續降低實際投入，年化報酬率的分母要用這個而不是原始成本
    it "目前投入資本 = 長腳成本 − 累積已實現" do
      create(:pmcc_pnl_event, position: position, realized_pnl: 417.4)

      expect(position.capital_deployed).to eq(24_100 - 417.4)
    end
  end
end
