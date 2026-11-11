# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HallOfFame models", type: :model do
  describe HallOfFame::Official do
    it "is valid with valid attributes" do
      expect(build(:hof_official)).to be_valid
    end

    it "uses the hof_ table prefix" do
      expect(described_class.table_name).to eq("hof_officials")
    end

    it "requires a unique slug" do
      create(:hof_official, slug: "pelosi")
      expect(build(:hof_official, slug: "pelosi")).not_to be_valid
    end

    it "rejects unknown category and source" do
      expect(build(:hof_official, category: "senate")).not_to be_valid
      expect(build(:hof_official, source: "senate")).not_to be_valid
    end
  end

  describe HallOfFame::Filing do
    it "is valid with valid attributes" do
      expect(build(:hof_filing)).to be_valid
    end

    it "defaults parse_status to pending" do
      expect(described_class.new.parse_status).to eq("pending")
    end

    it "rejects a duplicate (source, doc_id) at the model level" do
      create(:hof_filing, source: "house", doc_id: "20034836")
      expect(build(:hof_filing, source: "house", doc_id: "20034836")).not_to be_valid
    end

    it "raises RecordNotUnique when the unique index is violated" do
      create(:hof_filing, source: "house", doc_id: "20034836")
      duplicate = build(:hof_filing, source: "house", doc_id: "20034836")
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same doc_id under a different source" do
      create(:hof_filing, source: "house", doc_id: "ABC")
      expect(build(:hof_filing, source: "oge", doc_id: "ABC")).to be_valid
    end

    it "rejects unknown filing_type and parse_status" do
      expect(build(:hof_filing, filing_type: "13f")).not_to be_valid
      expect(build(:hof_filing, parse_status: "skipped")).not_to be_valid
    end
  end

  describe HallOfFame::Holding do
    it "allows value_max to be nil (unbounded range)" do
      holding = build(:hof_holding, value_label: "Over $50,000,000", value_min: 50_000_001, value_max: nil)
      expect(holding).to be_valid
    end

    it "rejects unknown owner" do
      expect(build(:hof_holding, owner: "XX")).not_to be_valid
    end
  end

  describe HallOfFame::Trade do
    it "maps to hof_transactions" do
      expect(described_class.table_name).to eq("hof_transactions")
    end

    it "allows nil tx_type but rejects unknown values" do
      expect(build(:hof_trade, tx_type: nil)).to be_valid
      expect(build(:hof_trade, tx_type: "X")).not_to be_valid
    end

    it "keeps ActiveRecord#transaction intact on filings" do
      filing = create(:hof_filing)
      expect(filing.transaction { :ok }).to eq(:ok)
    end
  end

  describe HallOfFame::OptionDetail do
    it "belongs to a trade via transaction_id" do
      detail = create(:hof_option_detail)
      expect(detail.trade.option_detail).to eq(detail)
    end

    it "allows only one detail per trade" do
      detail = create(:hof_option_detail)
      expect(build(:hof_option_detail, trade: detail.trade)).not_to be_valid
    end

    it "rejects unknown option_right and premium_source" do
      expect(build(:hof_option_detail, option_right: "straddle")).not_to be_valid
      expect(build(:hof_option_detail, premium_source: "guess")).not_to be_valid
    end
  end

  describe HallOfFame::SyncRun do
    it "defaults counters and http_validators" do
      run = create(:hof_sync_run)
      expect(run.new_filings_count).to eq(0)
      expect(run.error_count).to eq(0)
      expect(run.http_validators).to eq({})
    end
  end

  describe "dependent records" do
    it "destroys holdings, trades and option details with the filing" do
      filing = create(:hof_filing)
      create(:hof_holding, filing: filing)
      trade = create(:hof_trade, filing: filing)
      create(:hof_option_detail, trade: trade)

      expect { filing.destroy }
        .to change(HallOfFame::Holding, :count).by(-1)
        .and change(HallOfFame::Trade, :count).by(-1)
        .and change(HallOfFame::OptionDetail, :count).by(-1)
    end

    it "refuses to destroy an official that still has filings" do
      filing = create(:hof_filing)
      expect { filing.official.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end
end
