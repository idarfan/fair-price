# frozen_string_literal: true

require "rails_helper"

RSpec.describe BullCallSpreadCalculatorService do
  describe "#call" do
    it "computes the standard debit spread formulas" do
      result = described_class.new(k1: 70.0, k1_ask: 8.00, k2: 80.0, k2_bid: 4.10).call

      expect(result.debit).to eq(3.90)
      expect(result.cost_per_contract).to eq(390.0)
      expect(result.max_loss).to eq(390.0)
      expect(result.max_profit).to eq(610.0)
      expect(result.breakeven).to eq(73.9)
      expect(result.risk_reward).to eq((610.0 / 390.0).round(2))
      expect(result.warning).to be_nil
    end

    it "computes S* (crossover price), naked-buy comparison, and spread max value" do
      result = described_class.new(k1: 7.0, k1_ask: 4.90, k2: 12.0, k2_bid: 2.96).call

      # S* = K2 + K2_bid
      expect(result.s_star).to eq(14.96)
      expect(result.naked_cost).to eq(490.0)
      expect(result.naked_breakeven).to eq(11.9)
      expect(result.spread_max_value).to eq(500.0)
    end

    it "computes closeout_value, closeout_profit and realized_pct when k1_bid and k2_ask are given" do
      result = described_class.new(
        k1: 7.0, k1_ask: 4.90, k1_bid: 4.70,
        k2: 12.0, k2_bid: 2.96, k2_ask: 3.10
      ).call

      expect(result.closeout_value).to eq(((4.70 - 3.10) * 100).round(2))
      # Y = (現值−成本) ÷ 最大獲利, NOT 現值÷最大價值 (bcvs.md 修訂版公式)
      expect(result.closeout_profit).to eq((result.closeout_value - result.cost_per_contract).round(2))
      expect(result.realized_pct).to eq((result.closeout_profit / result.max_profit * 100).round(1))
    end

    it "matches the bcvs.md worked example: cost $194, max_profit $306, value $250 -> Y ≈ 18%" do
      # K1=7 (ask 4.90), K2=12 (bid 2.96) -> debit=1.94, cost=$194, max_profit=$306
      # closeout value ≈ $250 -> k1_bid - k2_ask = 2.50 -> pick k1_bid=4.60, k2_ask=2.10
      result = described_class.new(
        k1: 7.0, k1_ask: 4.90, k1_bid: 4.60,
        k2: 12.0, k2_bid: 2.96, k2_ask: 2.10
      ).call

      expect(result.cost_per_contract).to eq(194.0)
      expect(result.max_profit).to eq(306.0)
      expect(result.closeout_value).to eq(250.0)
      expect(result.closeout_profit).to eq(56.0)
      expect(result.realized_pct).to be_within(0.5).of(18.3)
    end

    it "returns nil closeout_value, closeout_profit and realized_pct when k1_bid or k2_ask are missing" do
      result = described_class.new(k1: 7.0, k1_ask: 4.90, k2: 12.0, k2_bid: 2.96).call
      expect(result.closeout_value).to be_nil
      expect(result.closeout_profit).to be_nil
      expect(result.realized_pct).to be_nil
    end

    it "computes debit_mid when both mid inputs are given" do
      result = described_class.new(
        k1: 70.0, k1_ask: 8.00, k1_bid: 7.80,
        k2: 80.0, k2_bid: 4.10, k2_ask: 4.30
      ).call

      expect(result.debit_mid).to eq(3.7)
    end

    it "returns nil debit_mid when mid inputs are missing" do
      result = described_class.new(k1: 70.0, k1_ask: 8.00, k2: 80.0, k2_bid: 4.10).call
      expect(result.debit_mid).to be_nil
    end

    it "flags invalid_width when K2 is not above K1" do
      result = described_class.new(k1: 70.0, k1_ask: 8.00, k2: 70.0, k2_bid: 4.10).call

      expect(result.warning).to eq(:invalid_width)
      expect(result.debit).to be_nil
      expect(result.risk_reward).to be_nil
    end

    it "flags invalid_width when K2 is below K1" do
      result = described_class.new(k1: 70.0, k1_ask: 8.00, k2: 65.0, k2_bid: 4.10).call
      expect(result.warning).to eq(:invalid_width)
    end

    it "flags non_debit and withholds risk_reward when net cost is not positive" do
      result = described_class.new(k1: 70.0, k1_ask: 3.00, k2: 80.0, k2_bid: 4.10).call

      expect(result.debit).to be <= 0
      expect(result.warning).to eq(:non_debit)
      expect(result.risk_reward).to be_nil
      expect(result.max_loss).not_to be_nil
    end

    it "never produces NaN or Infinity for a well-formed spread" do
      result = described_class.new(k1: 70.0, k1_ask: 8.00, k2: 80.0, k2_bid: 4.10).call

      [ result.debit, result.max_profit, result.max_loss, result.breakeven, result.risk_reward ].each do |v|
        expect(v.finite?).to eq(true)
      end
    end
  end
end
