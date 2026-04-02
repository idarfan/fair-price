# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarginInterestService do
  describe ".rate_for" do
    {
      1_000_000 => 0.08,
        999_999 => 0.086,
        500_000 => 0.086,
        499_999 => 0.105,
        250_000 => 0.105,
        249_999 => 0.1075,
        100_000 => 0.1075,
         99_999 => 0.1125,
         25_000 => 0.1125,
         24_999 => 0.1175,
         10_000 => 0.1175,
          9_999 => 0.12,
              0 => 0.12
    }.each do |balance, expected_rate|
      it "returns #{expected_rate} for balance #{balance}" do
        expect(described_class.rate_for(balance)).to eq(expected_rate)
      end
    end
  end

  describe ".accrued_interest" do
    it "calculates interest for TQQQ 100 shares over 60 days (12% tier)" do
      position = build(:margin_position, :tqqq, opened_on: 60.days.ago.to_date)
      # balance = 30 * 100 = 3000, rate = 12%, days = 60
      # 3000 * 0.12 * 60 / 360 = 60.0
      expect(described_class.accrued_interest(position)).to eq(60.0)
    end

    it "uses closed_on date when position is closed" do
      position = build(:margin_position, :tqqq, :closed,
                       opened_on: 30.days.ago.to_date,
                       closed_on: 10.days.ago.to_date)
      days = 20
      expected = (3000 * 0.12 * days / 360.0).round(2)
      expect(described_class.accrued_interest(position)).to eq(expected)
    end
  end

  describe ".first_charge_date" do
    it "returns opened_on + 14 days" do
      position = build(:margin_position, opened_on: Date.new(2026, 1, 1))
      expect(described_class.first_charge_date(position)).to eq(Date.new(2026, 1, 15))
    end
  end

  describe ".next_charge_date" do
    it "returns first charge date when before day 15" do
      position = build(:margin_position, opened_on: 5.days.ago.to_date)
      expect(described_class.next_charge_date(position)).to eq(position.opened_on + 14)
    end

    it "returns the next 30-day charge date after first charge" do
      position = build(:margin_position, opened_on: 20.days.ago.to_date)
      # first charge was opened_on + 14 (6 days ago), next = first + 30
      first = position.opened_on + 14
      expect(described_class.next_charge_date(position)).to eq(first + 30)
    end
  end

  describe ".days_held" do
    it "returns days from opened_on to today for open positions" do
      position = build(:margin_position, opened_on: 30.days.ago.to_date)
      expect(described_class.days_held(position)).to eq(30)
    end

    it "returns days from opened_on to closed_on for closed positions" do
      position = build(:margin_position, :closed,
                       opened_on: 30.days.ago.to_date,
                       closed_on: 10.days.ago.to_date)
      expect(described_class.days_held(position)).to eq(20)
    end
  end

  describe ".decorate" do
    it "returns a hash with all computed fields" do
      position = build(:margin_position, :tqqq, opened_on: 30.days.ago.to_date)
      result = described_class.decorate(position)
      expect(result).to include(
        :symbol, :buy_price, :shares, :balance, :annual_rate,
        :days_held, :accrued_interest, :next_charge_date, :current_period_interest
      )
      expect(result[:balance]).to eq(3000.0)
      expect(result[:annual_rate]).to eq(0.12)
      expect(result[:days_held]).to eq(30)
    end
  end
end
