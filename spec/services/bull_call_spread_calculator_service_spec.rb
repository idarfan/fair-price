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
