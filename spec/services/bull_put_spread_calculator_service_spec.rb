# frozen_string_literal: true

require "rails_helper"

RSpec.describe BullPutSpreadCalculatorService do
  describe "normal credit spread" do
    subject(:result) do
      described_class.new(short_strike: 75.0, short_bid: 3.20, long_strike: 70.0, long_ask: 1.70).call
    end

    it "computes net_credit = (short_bid - long_ask) * 100" do
      expect(result.net_credit).to eq(150.0)
    end

    it "computes width = short_strike - long_strike" do
      expect(result.width).to eq(5.0)
    end

    it "computes max_profit = net_credit" do
      expect(result.max_profit).to eq(150.0)
    end

    it "computes max_loss = width*100 - net_credit" do
      expect(result.max_loss).to eq(350.0)
    end

    it "sets margin = max_loss" do
      expect(result.margin).to eq(350.0)
    end

    it "computes breakeven = short_strike - net_credit/100" do
      expect(result.breakeven).to eq(73.5)
    end

    it "computes roc as a percentage rounded to 1 decimal" do
      expect(result.roc).to eq(42.9) # 150/350*100 = 42.857...
    end

    it "computes risk_reward (the X in 1:X) rounded to 2 decimals" do
      expect(result.risk_reward).to eq(2.33) # 350/150 = 2.333...
    end

    it "has no warning" do
      expect(result.warning).to be_nil
    end
  end

  describe "debit combination (net_credit < 0)" do
    subject(:result) do
      described_class.new(short_strike: 75.0, short_bid: 1.00, long_strike: 70.0, long_ask: 1.50).call
    end

    it "still computes the raw numbers" do
      expect(result.net_credit).to eq(-50.0)
      expect(result.max_loss).to eq(550.0)
      expect(result.breakeven).to eq(75.5)
    end

    it "flags warning :debit" do
      expect(result.warning).to eq(:debit)
    end

    it "does not output roc or risk_reward" do
      expect(result.roc).to be_nil
      expect(result.risk_reward).to be_nil
    end
  end

  describe "net_credit exactly 0" do
    subject(:result) do
      described_class.new(short_strike: 75.0, short_bid: 1.70, long_strike: 70.0, long_ask: 1.70).call
    end

    it "flags warning :debit (net_credit <= 0)" do
      expect(result.warning).to eq(:debit)
    end

    it "does not divide by zero or output NaN/Infinity" do
      expect(result.roc).to be_nil
      expect(result.risk_reward).to be_nil
      expect(result.max_loss).to eq(500.0)
    end
  end

  describe "invalid width (CSP strike not higher than protection strike)" do
    subject(:result) do
      described_class.new(short_strike: 70.0, short_bid: 2.0, long_strike: 75.0, long_ask: 1.0).call
    end

    it "flags warning :invalid_width and outputs no derived numbers" do
      expect(result.warning).to eq(:invalid_width)
      expect(result.net_credit).to be_nil
      expect(result.max_loss).to be_nil
      expect(result.roc).to be_nil
      expect(result.risk_reward).to be_nil
    end
  end

  describe "equal strikes (zero width)" do
    subject(:result) do
      described_class.new(short_strike: 75.0, short_bid: 2.0, long_strike: 75.0, long_ask: 1.0).call
    end

    it "flags warning :invalid_width" do
      expect(result.warning).to eq(:invalid_width)
    end
  end

  describe "very wide spread (large max_loss, small ROC)" do
    subject(:result) do
      described_class.new(short_strike: 100.0, short_bid: 5.0, long_strike: 50.0, long_ask: 2.0).call
    end

    it "still produces finite numbers" do
      expect(result.width).to eq(50.0)
      expect(result.net_credit).to eq(300.0)
      expect(result.max_loss).to eq(4700.0)
      expect(result.roc).to eq(6.4) # 300/4700*100 = 6.3829..., rounded to 1 decimal
    end
  end
end
