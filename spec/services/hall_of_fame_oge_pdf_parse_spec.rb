# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OgePdfParse do
  let(:storage_dir) { Rails.root.join("tmp/spec_hof_oge_storage") }
  let(:sidecar)     { instance_double(HallOfFame::OgeParserSidecar) }
  let(:service)     { described_class.new(sidecar:, storage_dir:, pause_seconds: 0) }
  let(:official)    { create(:hof_official, slug: "bessent", category: "executive", source: "oge") }
  let(:pdf_url)     { "https://extapps2.oge.gov/201/Presiden.nsf/PAS+Index/CF8CA0328CB1970085258E7B002D9B7E/$FILE/x.pdf" }
  let!(:annual) do
    create(:hof_filing, official:, source: "oge", doc_id: "CF8CA0328CB1970085258E7B002D9B7E", filing_type: "oge_278e",
                        year: 2026, pdf_url:)
  end
  let(:holding_row) do
    { "owner" => "SP", "asset_name" => "IRA #1 › SPDR S&P 500 ETF IV (SPY)", "ticker" => "SPY", "asset_type" => nil,
      "value_label" => "$100,001 - $250,000", "value_min" => 100_001, "value_max" => 250_000, "page" => 5, "part" => 5, "number" => "1.2" }
  end

  def sidecar_returns(status: "parsed", reasons: [], rows: [ holding_row ], ratio: 0.9991)
    allow(sidecar).to receive(:parse).and_return(
      { "status" => status, "reasons" => reasons, "marker_count" => rows.size, "container_count" => 0,
        "textlayer" => { "ratio" => ratio, "usable" => ratio >= 0.95 }, "rows" => rows }
    )
  end

  before { WebMock.stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.4 oge") }
  after  { FileUtils.rm_rf(storage_dir) }

  it "stores the PDF under oge/{year}, writes holdings and prefixes parse_error with the text-layer verdict" do
    sidecar_returns

    summary = service.call

    expect(summary.counts).to eq("parsed" => 1)
    expect(sidecar).to have_received(:parse).with(storage_dir.join("2026/CF8CA0328CB1970085258E7B002D9B7E.pdf"), "annual")
    expect(annual.reload).to have_attributes(parse_status: "parsed", parse_error: "textlayer: 99.91%（可用）")
    expect(annual.holdings.pluck(:owner, :asset_name, :ticker, :value_min, :value_max))
      .to eq([ [ "SP", "IRA #1 › SPDR S&P 500 ETF IV (SPY)", "SPY", 100_001, 250_000 ] ])
  end

  it "keeps needs_review reasons after the text-layer line" do
    sidecar_returns(status: "needs_review", reasons: [ "第 8 頁 #4.5 未知金額標籤：'$250,000 - $500,000'" ])

    service.call

    expect(annual.reload.parse_error).to eq("textlayer: 99.91%（可用）\n第 8 頁 #4.5 未知金額標籤：'$250,000 - $500,000'")
  end

  it "records an unusable text layer for Q3 OCR" do
    sidecar_returns(status: "needs_review", reasons: [ "文字層不可用（可讀比例 80.00%），待 Q3 OCR" ], rows: [], ratio: 0.8)

    service.call

    expect(annual.reload).to have_attributes(parse_status: "needs_review",
                                             parse_error: "textlayer: 80.00%（不可用）\n文字層不可用（可讀比例 80.00%），待 Q3 OCR")
  end

  it "only picks pending OGE 278e filings (278-T is left for Q3, House is untouched)" do
    create(:hof_filing, official:, source: "oge", filing_type: "oge_278t", pdf_url: "https://extapps2.oge.gov/t.pdf")
    create(:hof_filing, source: "house", filing_type: "annual", pdf_url: "https://disclosures-clerk.house.gov/a.pdf")
    sidecar_returns

    expect(service.call.counts).to eq("parsed" => 1)
    expect(HallOfFame::Filing.where(parse_status: "pending").pluck(:filing_type)).to contain_exactly("oge_278t", "annual")
  end

  it "marks the filing failed when the sidecar crashes" do
    allow(sidecar).to receive(:parse).and_raise(HallOfFame::OgeParserSidecar::Error, "sidecar 結束碼 124")

    expect(service.call.counts).to eq("failed" => 1)
    expect(annual.reload).to have_attributes(parse_status: "failed", parse_error: "sidecar 結束碼 124")
  end

  describe "with the real Python sidecar" do
    before { skip "名人堂 venv 未建立" unless File.exist?(HallOfFame::HouseParserSidecar::PYTHON) }

    let(:service) { described_class.new(storage_dir:, pause_seconds: 0) }

    it "parses the Bessent 2026 annual end to end" do
      WebMock.stub_request(:get, pdf_url)
             .to_return(status: 200, body: Rails.root.join("spec/fixtures/hall_of_fame/oge/bessent_2026.pdf").binread)

      expect(service.call.counts).to eq("parsed" => 1)
      expect(annual.reload.holdings.count).to eq(58)
      expect(annual.holdings.where(owner: "SP").pluck(:ticker)).to include("SPY", "MITTX")
      expect(annual.parse_error).to eq("textlayer: 99.91%（可用）")
    end
  end
end
