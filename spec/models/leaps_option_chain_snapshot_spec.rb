# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeapsOptionChainSnapshot, type: :model do
  # fresh window 邊界測試（spec「fresh window 5 → 30 分鐘」節）：
  # 用 FRESH_WINDOW ± 1.minute 表達邊界，不寫死 29/31 分鐘字面值。
  describe ".fresh scope boundary" do
    let(:base_attrs) do
      {
        symbol: "FWTEST", expiration_date: Date.new(2028, 1, 21),
        strike: 10.0, option_type: "Call"
      }
    end

    after { described_class.where(symbol: "FWTEST").delete_all }

    it "FRESH_WINDOW is 30 minutes (single source of truth)" do
      expect(described_class::FRESH_WINDOW).to eq(30.minutes)
    end

    it "includes rows scraped just inside the window" do
      travel_to Time.current do
        described_class.create!(
          base_attrs.merge(scraped_at: (described_class::FRESH_WINDOW - 1.minute).ago)
        )
        expect(described_class.for_symbol("FWTEST").fresh.exists?).to be true
      end
    end

    it "excludes rows scraped just outside the window" do
      travel_to Time.current do
        described_class.create!(
          base_attrs.merge(scraped_at: (described_class::FRESH_WINDOW + 1.minute).ago)
        )
        expect(described_class.for_symbol("FWTEST").fresh.exists?).to be false
      end
    end
  end
end
