# frozen_string_literal: true

require "rails_helper"

# tasks/leaps-vertical-fix.md S1：同一組公式分別以 mid 淨成本與保守淨成本（LC ask − SC bid）計算全部指標。
# FX-1：LC 100 bid 74.95／ask 79.05（mid 77.00）、SC 240 bid 29.70／ask 33.70（mid 31.70），寬度 140。
RSpec.describe LeapsVerticalSpreadService::Metrics do
  let(:tolerance) { BigDecimal("0.005") } # 通則 7：測試比對容差 ±0.005
  let(:long_leg)  { { strike: BigDecimal("100"), bid: BigDecimal("74.95"), ask: BigDecimal("79.05") } }
  let(:short_leg) { { strike: BigDecimal("240"), bid: BigDecimal("29.70"), ask: BigDecimal("33.70") } }

  def dual(long: long_leg, short: short_leg, contracts: 1, fee: "0", target: "200")
    described_class.dual(long: long, short: short, contracts: contracts,
                         fee_per_leg: BigDecimal(fee), target_price: target && BigDecimal(target))
  end

  def expect_close(actual, expected)
    expect((actual - BigDecimal(expected.to_s)).abs).to be <= tolerance
  end

  describe "FX-1，到期股價 200、1 口、費用 0" do
    subject(:result) { dual }

    {
      mid:          { net_cost: "4530", max_profit: "9470", max_loss: "4530", breakeven: "145.30",
                      risk_reward: "2.09", pnl: "5470", return_ratio: "1.2075" },
      conservative: { net_cost: "4935", max_profit: "9065", max_loss: "4935", breakeven: "149.35",
                      risk_reward: "1.84", pnl: "5065", return_ratio: "1.0263" }
    }.each do |basis, expected|
      it "#{basis} 基準的六項指標" do
        m = result[basis]
        expect_close(m[:net_cost], expected[:net_cost])
        expect_close(m[:max_profit], expected[:max_profit])
        expect_close(m[:max_loss], expected[:max_loss])
        expect_close(m[:breakeven], expected[:breakeven])
        expect_close(m[:risk_reward], expected[:risk_reward])
        expect_close(m[:payoff][:pnl], expected[:pnl])
        # 百分比四捨五入到 2 位後比對：+120.75%、+102.63%
        expect_close((m[:payoff][:return_ratio] * 100).round(2), BigDecimal(expected[:return_ratio]) * 100)
      end

      it "#{basis} 基準滿足檢核式：最大獲利 + 最大虧損 = 寬度 × 100 × 口數" do
        m = result[basis]
        expect(m[:max_profit] + m[:max_loss]).to eq(BigDecimal("14000"))
      end
    end

    it "兩個基準都有獲利空間" do
      expect(result[:no_profit_room]).to be(false)
      expect(result[:mid][:no_profit_room]).to be(false)
      expect(result[:conservative][:no_profit_room]).to be(false)
    end

    it "2 口時兩個基準都滿足檢核式" do
      two = dual(contracts: 2)
      %i[mid conservative].each do |basis|
        expect(two[basis][:max_profit] + two[basis][:max_loss]).to eq(BigDecimal("28000"))
      end
    end
  end

  describe "邊界：保守淨成本 ≥ 寬度" do
    it "LC ask 160、SC bid 10 → no_profit_room，最大獲利 ≤ 0" do
      result = dual(long: long_leg.merge(ask: BigDecimal("160")), short: short_leg.merge(bid: BigDecimal("10")))
      expect(result[:no_profit_room]).to be(true)
      expect(result[:conservative][:no_profit_room]).to be(true)
      expect(result[:conservative][:max_profit]).to be <= 0
    end
  end

  describe "S1-b 口數與費用（FX-1，2 口、費率 0.05，mid 基準）" do
    subject(:mid) { dual(contracts: 2, fee: "0.05")[:mid] }

    it "淨成本、最大虧損、最大獲利、兩平" do
      expect_close(mid[:net_cost], "9060.00")
      expect_close(mid[:max_loss], "9060.20")
      expect_close(mid[:max_profit], "18939.60")
      expect_close(mid[:breakeven], "145.30")
    end
  end

  describe "到期損益的費用" do
    it "到期作廢（股價低於 K_L）只扣開倉費用，等於 −最大虧損" do
      m = dual(fee: "0.05", target: "90")[:mid]
      expect(m[:payoff][:pnl]).to eq(-m[:max_loss])
    end

    it "股價高於 K_S 時扣來回費用，等於最大獲利" do
      m = dual(fee: "0.05", target: "300")[:mid]
      expect(m[:payoff][:pnl]).to eq(m[:max_profit])
    end
  end

  it "沒有預估股價時不算到期損益" do
    expect(dual(target: nil)[:mid][:payoff]).to be_nil
  end

  it "任一腳缺 bid／ask（盤後以 last 為價）：mid 基準用 service 的 price，沒有保守基準" do
    result = dual(short: short_leg.merge(bid: nil, price: BigDecimal("31.70")))
    expect_close(result[:mid][:net_cost], "4530")
    expect(result[:conservative]).to be_nil
    expect(result[:no_profit_room]).to be_nil
  end

  it "有 price 時 mid 基準以 price 為準（與 service 的 priced 一致）" do
    result = dual(long: long_leg.merge(price: BigDecimal("77.00")), short: short_leg.merge(price: BigDecimal("31.70")))
    expect_close(result[:mid][:net_cost], "4530")
  end
end
