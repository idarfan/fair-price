# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarginPosition, type: :model do
  subject(:position) { build(:margin_position) }

  describe "validations" do
    it { is_expected.to be_valid }

    it "upcases symbol on validation" do
      position.symbol = "aapl"
      position.valid?
      expect(position.symbol).to eq("AAPL")
    end

    it "strips whitespace from symbol" do
      position.symbol = " AAPL "
      position.valid?
      expect(position.symbol).to eq("AAPL")
    end

    it "rejects invalid symbol format" do
      position.symbol = "INVALID!!"
      expect(position).not_to be_valid
      expect(position.errors[:symbol]).to be_present
    end

    it "requires buy_price > 0" do
      position.buy_price = 0
      expect(position).not_to be_valid
    end

    it "requires shares > 0" do
      position.shares = 0
      expect(position).not_to be_valid
    end

    it "allows nil sell_price" do
      position.sell_price = nil
      expect(position).to be_valid
    end

    it "rejects sell_price <= 0" do
      position.sell_price = -1
      expect(position).not_to be_valid
    end

    it "requires opened_on" do
      position.opened_on = nil
      expect(position).not_to be_valid
    end

    it "rejects invalid status" do
      position.status = "pending"
      expect(position).not_to be_valid
    end
  end

  describe "#balance" do
    it "returns buy_price * shares" do
      position.buy_price = 180.0
      position.shares    = 100.0
      expect(position.balance).to eq(18_000.0)
    end
  end

  describe "#open?" do
    it "returns true when status is open" do
      expect(position).to be_open
    end

    it "returns false when status is closed" do
      position.status = "closed"
      expect(position).not_to be_open
    end
  end

  describe "scopes" do
    before do
      create(:margin_position, symbol: "AAPL", status: "open")
      create(:margin_position, :closed, symbol: "TSLA")
    end

    it "open_positions returns only open" do
      expect(MarginPosition.open_positions.pluck(:status).uniq).to eq([ "open" ])
    end

    it "closed_positions returns only closed" do
      expect(MarginPosition.closed_positions.pluck(:status).uniq).to eq([ "closed" ])
    end
  end
end
