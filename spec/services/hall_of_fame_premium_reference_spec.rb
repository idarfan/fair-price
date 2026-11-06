# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::PremiumReference do
  let(:barchart)   { instance_double(HallOfFame::BarchartOptionHistory) }
  let(:underlying) { instance_double(HallOfFame::UnderlyingHistory) }
  let(:reference)  { described_class.new(barchart:, underlying:, bs_config: { "risk_free_rate" => 0.04, "volatility_window" => 30 }) }
  let(:parsed)     { HallOfFame::OptionDescriptionParser.new.parse("Call options; Strike price $340; Expires 10/16/2026") }
  let(:url)        { "https://www.barchart.com/stocks/quotes/MSFT%7C20261016%7C340.00C/price-history/historical" }
  let(:tx_date)    { Date.new(2026, 8, 14) }

  def page(status, rows) = { "status" => status, "url" => url, "rows" => rows }

  def resolve(cdp_online: true) = reference.resolve(ticker: "MSFT", parsed:, tx_date:, cdp_online:)

  it "uses the Barchart DOM close of the trade date" do
    allow(barchart).to receive(:fetch).with("MSFT|20261016|340.00C")
                                      .and_return(page("success", [ { "date" => "2026-08-14", "close" => 61.5, "volume" => 28, "underlying" => 401.2 } ]))

    ref = resolve

    expect(ref).to have_attributes(status: :ok, source: "barchart_dom", value: BigDecimal("61.5"), underlying: BigDecimal("401.2"))
    expect(ref.note).to include(url, "2026-08-14 收盤 61.5（成交量 28）")
  end

  # 實測：無成交日 lastPrice=0（畫面 N/A），或 volume=null 而價格沿用前一日。
  [ { "close" => 0, "volume" => nil }, { "close" => 165.02, "volume" => nil }, { "close" => 165.02, "volume" => 0 } ].each do |row|
    it "does not treat a no-trade row (#{row}) as the day's close" do
      allow(barchart).to receive(:fetch).and_return(page("success", [ row.merge("date" => "2026-08-14", "underlying" => 401.2) ]))
      allow(underlying).to receive_messages(close_on: 400.0, closes_before: Array.new(31) { |i| 380.0 + ((i % 2) * 4) })

      ref = resolve

      expect(ref.source).to eq("bs_model")
      expect(ref.note).to include("成交日 2026-08-14 當天無成交")
    end
  end

  it "falls back to bs_model only when CDP is online and the date is not visible" do
    allow(barchart).to receive(:fetch).and_return(page("empty", []))
    closes = Array.new(31) { |i| 380.0 + ((i % 2) * 4) }
    allow(underlying).to receive_messages(close_on: 400.0, closes_before: closes)

    ref = resolve

    expect(ref).to have_attributes(status: :ok, source: "bs_model", underlying: BigDecimal("400.0"))
    expect(ref.value).to be > 60
    expect(ref.note).to include("可見 0 列，不含成交日 2026-08-14", "模型估算 Black-Scholes", "r=0.04")
    expect(underlying).to have_received(:closes_before).with("MSFT", tx_date, 31)
  end

  it "does not touch Barchart or the model when CDP is offline" do
    allow(barchart).to receive(:fetch)
    allow(underlying).to receive(:close_on)

    ref = resolve(cdp_online: false)

    expect(ref).to have_attributes(status: :cdp_offline, value: nil, note: "CDP 未連線，待重試")
    expect(barchart).not_to have_received(:fetch)
    expect(underlying).not_to have_received(:close_on)
  end

  it "reports a Barchart failure without substituting bs_model" do
    allow(barchart).to receive(:fetch).and_return({ "status" => "barchart_session_expired" })
    allow(underlying).to receive(:close_on)

    ref = resolve

    expect(ref).to have_attributes(status: :error, value: nil)
    expect(ref.note).to include("barchart_session_expired")
    expect(underlying).not_to have_received(:close_on)
  end

  it "reports an error when stock history is missing for bs_model" do
    allow(barchart).to receive(:fetch).and_return(page("success", [ { "date" => "2026-09-01", "close" => 70, "underlying" => 410 } ]))
    allow(underlying).to receive_messages(close_on: nil, closes_before: nil)

    expect(resolve).to have_attributes(status: :error, value: nil)
  end
end
