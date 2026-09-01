# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccPnlService do
  let(:position) do
    create(:pmcc_position, long_contracts: 1, long_strike: 100, long_entry_cost: 120.5,
                           long_entry_date: Date.current - 100)
  end

  describe "各事件類型的已實現金額" do
    let(:leg) { build(:pmcc_short_leg, contracts: 1, premium_collected: 3.2) }

    it "到期歸零：收租全部落袋" do
      expect(described_class.short_expired_pnl(leg)).to eq(320.0)
    end

    it "買回平倉：收租減買回成本" do
      expect(described_class.short_closed_pnl(leg, close_cost: 1.1)).to eq(210.0)
    end

    it "買回成本高於收租時是負數" do
      expect(described_class.short_closed_pnl(leg, close_cost: 5.0)).to eq(-180.0)
    end

    # 長腳因指派而行權/平倉要另開事件記，不能把估算損失減進這裡
    it "被指派：只記短腳自己的現金流" do
      expect(described_class.short_assigned_pnl(leg, close_cost: 2.0)).to eq(120.0)
    end

    it "長腳平倉：賣出價減實付成本" do
      expect(described_class.long_closed_pnl(position, sell_price: 130.0)).to eq(950.0)
    end

    it "手續費一律扣掉" do
      expect(described_class.short_closed_pnl(leg, close_cost: 1.1, fees: 2.6)).to eq(207.4)
    end

    it "口數會乘進去（原 spec 隱含只有 1 口）" do
      two = build(:pmcc_short_leg, contracts: 2, premium_collected: 3.2)

      expect(described_class.short_expired_pnl(two)).to eq(640.0)
    end
  end

  # pmcc-tracker Phase 4 驗收：3 筆模擬 roll（含 1 筆 assigned）後
  # 累積已實現與手算一致，且不含任何估算值
  describe "驗收：三筆事件後的累積已實現" do
    before do
      create(:pmcc_pnl_event, position: position, event_type: "short_closed",
                              realized_pnl: 210.0, fees: 0, occurred_at: 3.days.ago)
      create(:pmcc_pnl_event, position: position, event_type: "short_expired",
                              realized_pnl: 320.0, fees: 0, occurred_at: 2.days.ago)
      create(:pmcc_pnl_event, position: position, event_type: "short_assigned",
                              realized_pnl: 120.0, fees: 0, occurred_at: 1.day.ago)
    end

    it "累積已實現 = 三筆加總" do
      expect(described_class.call(position, long_quote: nil)[:realized]).to eq(650.0)
    end

    it "時間軸依發生順序，型別完整" do
      timeline = described_class.call(position, long_quote: nil)[:timeline]

      expect(timeline.map { |e| e[:event_type] })
        .to eq(%w[short_closed short_expired short_assigned])
    end
  end

  describe "未實現損益" do
    let(:quote) { build(:pmcc_leg_quote, mid: 129.7, scraped_at: Time.current) }

    it "(市價 − 實付成本) × 口數 × 100" do
      expect(described_class.call(position, long_quote: quote)[:unrealized]).to eq(920.0)
    end

    it "多口會乘進去" do
      position.update!(long_contracts: 3)

      expect(described_class.call(position, long_quote: quote)[:unrealized]).to eq(2760.0)
    end

    # 沒報價回 nil 而不是 0：0 會讓使用者以為系統確認過沒有浮動
    it "沒有長腳報價時回 nil，不當成 0" do
      res = described_class.call(position, long_quote: nil)

      expect(res[:unrealized]).to be_nil
      expect(res[:total]).to be_nil
    end

    it "未實現不寫進帳本（realized 不受影響）" do
      create(:pmcc_pnl_event, position: position, realized_pnl: 210.0)

      expect(described_class.call(position, long_quote: quote)[:realized]).to eq(210.0)
      expect(PmccPnlEvent.count).to eq(1)
    end
  end

  describe "部位總損益與年化" do
    let(:quote) { build(:pmcc_leg_quote, mid: 129.7) }

    before { create(:pmcc_pnl_event, position: position, realized_pnl: 650.0) }

    it "總損益 = 已實現 + 未實現" do
      expect(described_class.call(position, long_quote: quote)[:total]).to eq(650.0 + 920.0)
    end

    # 分母用 capital_deployed（實付成本 − 累積已實現），不是原始成本：
    # 滾倉收租會持續降低實際投入，用原始成本會低估報酬
    it "年化用 capital_deployed 當分母" do
      res = described_class.call(position, long_quote: quote)
      capital = 12_050 - 650.0

      expect(res[:capital_deployed]).to eq(capital)
      expect(res[:annualized_return]).to eq((1570.0 / capital / 100 * 365).round(6))
    end

    it "當天建倉不會除以零" do
      position.update!(long_entry_date: Date.current)

      expect { described_class.call(position, long_quote: quote) }.not_to raise_error
      expect(described_class.call(position, long_quote: quote)[:holding_days]).to eq(0)
    end

    it "收租已超過長腳成本（資本回收完）時年化回 nil，不硬算" do
      create(:pmcc_pnl_event, position: position, realized_pnl: 20_000)

      expect(described_class.call(position, long_quote: quote)[:annualized_return]).to be_nil
    end

    it "未實現未知時總損益與年化都是 nil" do
      res = described_class.call(position, long_quote: nil)

      expect(res[:total]).to be_nil
      expect(res[:annualized_return]).to be_nil
    end

    it "已平倉的部位持有天數算到 closed_at" do
      position.update!(status: "closed", closed_at: (Date.current - 40).to_time)

      expect(described_class.call(position, long_quote: quote)[:holding_days]).to eq(60)
    end
  end

  it "長腳資訊同時給實付成本與市價，分開標示" do
    res = described_class.call(position, long_quote: build(:pmcc_leg_quote, mid: 129.7))

    expect(res[:long_leg][:entry_cost]).to eq(120.5)
    expect(res[:long_leg][:market_mid]).to eq(129.7)
  end
end
