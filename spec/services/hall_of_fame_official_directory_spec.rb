# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OfficialDirectory do
  let(:directory) { described_class.new }
  let(:official)  { create(:hof_official, slug: "pelosi", display_name: "Nancy Pelosi") }
  let(:ptr)       { create(:hof_filing, official:, filing_type: "ptr", parse_status: "parsed", filing_date: Date.new(2026, 8, 1)) }

  it "builds cards with latest filing date, PTR count and needs_review count" do
    ptr
    create(:hof_filing, official:, filing_type: "annual", parse_status: "needs_review", filing_date: Date.new(2026, 5, 15))
    create(:hof_official, category: "executive")

    expect(directory.cards("congress")).to eq([
      { slug: "pelosi", display_name: "Nancy Pelosi", district: "CA11", title: nil,
        latest_filing_date: Date.new(2026, 8, 1), ptr_count: 1, needs_review_count: 1 }
    ])
  end

  describe "#profile" do
    it "uses the latest annual and keeps invalid needs_review rows out of the shares" do
      old = create(:hof_filing, official:, filing_type: "annual", year: 2024, parse_status: "parsed")
      create(:hof_holding, filing: old, asset_name: "Old")
      latest = create(:hof_filing, official:, filing_type: "annual", year: 2025, parse_status: "needs_review", parse_error: "Undetermined")
      create(:hof_holding, filing: latest, asset_name: "Kept", value_min: 1_000, value_max: 3_000)
      HallOfFame::Holding.insert_all([
        { filing_id: latest.id, owner: "XX", asset_name: "Bad owner", value_label: "$1 - $1,000", value_min: 5, value_max: 10 },
        { filing_id: latest.id, owner: "self", asset_name: "Undetermined asset", value_label: "Undetermined", value_min: nil, value_max: nil }
      ])

      holdings = directory.profile(official)[:holdings]
      rows = holdings[:views][:all][:rows]

      expect(holdings).to include(year: 2025, as_of: "2025/12/31", parse_status: "needs_review")
      expect(rows.map { |r| [ r[:asset_name], r[:estimated], r[:excluded_reason] ] }).to eq([
        [ "Kept", 100.0, nil ],
        [ "Bad owner", nil, "持有人代碼未知（\"XX\"）" ],
        [ "Undetermined asset", nil, "金額無法對照（'Undetermined'）" ]
      ])
      expect(rows).to all(include(needs_review: true))
      expect(holdings[:views][:all][:excluded_count]).to eq(2)
    end

    it "lists 12 months of PTR trades with option labels and buy/sell shares computed separately" do
      travel_to(Date.new(2026, 10, 18)) do
        buy = create(:hof_trade, filing: ptr, ticker: "BE", tx_type: "P", tx_date: Date.new(2026, 7, 28), amount_min: 500_001, amount_max: 1_000_000)
        create(:hof_option_detail, trade: buy, contracts_stated: 100, premium_source: "stated_contracts",
                                   premium_implied_min: 50.0001, premium_implied_max: 100, calc_note: "申報 100 口")
        est = create(:hof_trade, filing: ptr, ticker: "MSFT", tx_type: "P", tx_date: Date.new(2026, 8, 14), amount_min: 250_001, amount_max: 500_000)
        create(:hof_option_detail, trade: est, contracts_est_min: 16, contracts_est_max: 31, premium_ref: 157.18, premium_source: "barchart_dom")
        create(:hof_trade, filing: ptr, ticker: "NVDA", tx_type: "S", tx_date: Date.new(2026, 9, 1), amount_min: 1_001, amount_max: 15_000)
        create(:hof_trade, filing: ptr, ticker: "OLD", tx_type: "P", tx_date: Date.new(2025, 10, 17))

        trades = directory.profile(official)[:trades]

        expect(trades[:rows].map { |r| r[:ticker] }).to eq(%w[NVDA MSFT BE])
        expect(trades[:rows].map { |r| r[:option]&.values_at(:contracts, :premium, :source_label) }).to eq([
          nil, [ "約 16～31 口", "$157.18", "Barchart 當日收盤" ], [ "申報 100 口", "$50.00～$100.00", "申報" ]
        ])
        # 買進：BE mid 750,000.5、MSFT mid 375,000.5，總和 1,125,001
        #   → BE 750,000.5 / 1,125,001 = 66.66670%、MSFT 33.33330%；賣出另算 NVDA 100%
        expect(trades[:shares][:purchase].map { |s| [ s[:key], s[:estimated] ] }).to eq([ [ "BE", 66.6667 ], [ "MSFT", 33.3333 ] ])
        expect(trades[:shares][:sale].map { |s| [ s[:key], s[:estimated] ] }).to eq([ [ "NVDA", 100.0 ] ])
      end
    end

    it "reports update times from finished sync runs per kind" do
      create(:hof_sync_run, kind: "index", finished_at: Time.zone.parse("2026-10-18 00:30:05"))
      create(:hof_sync_run, kind: "options", finished_at: nil)

      expect(directory.profile(official)[:synced_at]).to eq(
        "index" => Time.zone.parse("2026-10-18 00:30:05"), "pdf_parse" => nil, "options" => nil
      )
    end
  end
end
