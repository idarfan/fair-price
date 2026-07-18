# frozen_string_literal: true

require "rails_helper"

RSpec.describe BullCallSpreadRepairCalculatorService do
  describe "#call" do
    it "computes the locked result and breakeven basis threshold" do
      # width = 2, breakeven_basis = 2 + 0.60 = 2.60
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90).call

      expect(result.breakeven_basis).to eq(2.6)
      expect(result.locked_result).to eq((2.6 - 6.90).round(4))
      expect(result.warning).to eq(:locked_loss)
      expect(result.locked_result_total).to eq((result.locked_result * 100).round(2))
    end

    it "does not warn when basis is exactly at the breakeven threshold (boundary)" do
      # breakeven_basis = (12-10) + 0.60 = 2.60 -> basis == 2.60 -> locked_result == 0
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 2.60).call

      expect(result.locked_result).to eq(0.0)
      expect(result.warning).to be_nil
    end

    it "does not warn when basis is below the breakeven threshold" do
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 2.0).call

      expect(result.locked_result).to be > 0
      expect(result.warning).to be_nil
    end

    it "computes the below-K1 expiry scenario" do
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90).call
      expect(result.below_k1_pnl).to eq((0.60 - 6.90).round(4))
    end

    it "computes closeout proceeds and pnl when a current K1 bid is given" do
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90, k1_current_bid: 2.10).call

      expect(result.closeout_proceeds).to eq(210.0)
      expect(result.closeout_pnl).to eq(((2.10 - 6.90) * 100).round(2))
    end

    it "returns nil closeout figures when no current K1 bid is given" do
      result = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90).call
      expect(result.closeout_proceeds).to be_nil
      expect(result.closeout_pnl).to be_nil
    end
  end

  describe "#mid_pnl" do
    it "computes the intermediate K1<price<K2 P&L as a function of price" do
      service = described_class.new(k1: 10.0, k2: 12.0, k2_bid: 0.60, basis: 6.90)
      expect(service.mid_pnl(11.0)).to eq(((11.0 - 10.0) + 0.60 - 6.90).round(4))
    end
  end
end
