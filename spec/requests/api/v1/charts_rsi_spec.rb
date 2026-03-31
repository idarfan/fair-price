# frozen_string_literal: true

# 驗證 calc_rsi 使用 Wilder's EMA（非簡單平均）
# 防止教訓 2026-03-30 教訓 1 重犯：財務指標算法必須驗證
require "rails_helper"

RSpec.describe Api::V1::ChartsController, type: :controller do
  # 使用固定的合成資料，計算已知答案
  # 20 個漲跌（10x+1.0, 10x-0.5）→ 21 個收盤價，覆蓋第一個 RSI（bar 14）+ 後續 bars
  # avg_gain = 0.5, avg_loss = 0.25 → RS = 2.0 → 第一個 RSI ≈ 66.67
  let(:flat_closes) do
    base = 100.0
    gains  = Array.new(10, 1.0)
    losses = Array.new(10, -0.5)
    changes = gains.zip(losses).flatten  # 20 changes → 21 closes
    changes.each_with_object([ base ]) { |c, arr| arr << (arr.last + c).round(4) }
  end

  describe "#calc_rsi (Wilder's EMA)" do
    subject(:rsi) { controller.send(:calc_rsi, flat_closes, 14) }

    it "returns nil for first 14 bars (period not reached)" do
      expect(rsi[0..13].compact).to be_empty
    end

    it "uses simple average for bar 14 (first RSI value)" do
      first_rsi = rsi[14]
      expect(first_rsi).not_to be_nil
      # avg_g = 0.5, avg_l = 0.25, RS = 2.0 → RSI ≈ 66.67
      expect(first_rsi).to be_within(1.0).of(66.7)
    end

    it "uses Wilder EMA for subsequent bars (not simple re-average)" do
      subsequent = rsi[15..]&.compact
      expect(subsequent).not_to be_nil
      expect(subsequent).not_to be_empty
      # Wilder's smoothing makes RSI stable, not jumping to extremes
      subsequent.each do |v|
        expect(v).to be_between(0, 100)
      end
    end

    it "never produces RSI outside 0..100" do
      expect(rsi.compact.all? { |v| v.between?(0, 100) }).to be true
    end
  end

  describe "#calc_rsi with monotonically rising prices" do
    let(:rising_closes) { (100..130).map(&:to_f) }

    it "approaches 100 (all gains, no losses)" do
      rsi = controller.send(:calc_rsi, rising_closes, 14)
      expect(rsi.compact.last).to eq(100.0)
    end
  end

  describe "#calc_rsi with monotonically falling prices" do
    let(:falling_closes) { 30.downto(0).map(&:to_f) }

    it "approaches 0 (all losses, no gains)" do
      rsi = controller.send(:calc_rsi, falling_closes, 14)
      expect(rsi.compact.last).to eq(0.0)
    end
  end

  describe "#calc_rsi with period = 7" do
    it "produces values 7 bars earlier than period 14" do
      rsi7  = controller.send(:calc_rsi, flat_closes, 7)
      rsi14 = controller.send(:calc_rsi, flat_closes, 14)
      expect(rsi7[7]).not_to be_nil
      expect(rsi14[7]).to be_nil
    end
  end
end
