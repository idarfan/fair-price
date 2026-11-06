# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::HousePdfParse do
  let(:storage_dir) { Rails.root.join("tmp/spec_hof_storage") }
  let(:fixtures)    { Rails.root.join("spec/fixtures/hall_of_fame") }
  let(:sidecar)     { instance_double(HallOfFame::HouseParserSidecar) }
  let(:service)     { described_class.new(sidecar: sidecar, storage_dir: storage_dir, pause_seconds: 0) }
  let!(:ptr)        { create(:hof_filing, doc_id: "20035553", filing_type: "ptr", year: 2026, pdf_url: pdf_url("ptr", "20035553")) }
  let(:pdf_bytes)   { fixtures.join("20035553.pdf").binread }

  let(:trade_row) do
    { "owner" => "SP", "asset_name" => "REOF XXX, LLC [AB]", "ticker" => nil, "asset_type_code" => "AB",
      "tx_type" => "P", "tx_date" => "2026-09-08", "notified_date" => "2026-09-08",
      "amount_label" => "$500,001 - $1,000,000", "amount_min" => 500_001, "amount_max" => 1_000_000,
      "description" => "Investment in LLC" }
  end

  def pdf_url(type, doc_id) = HallOfFame::HouseIndexSync.pdf_url(type, 2026, doc_id)

  def sidecar_returns(status: "parsed", reasons: [], rows: [ trade_row ])
    allow(sidecar).to receive(:parse).and_return(
      { "status" => status, "reasons" => reasons, "marker_count" => rows.size, "rows" => rows }
    )
  end

  before { WebMock.stub_request(:get, ptr.pdf_url).to_return(status: 200, body: pdf_bytes) }
  after  { FileUtils.rm_rf(storage_dir) }

  it "downloads the PDF, stores it with sha256 and writes trades" do
    sidecar_returns
    summary = service.call

    path = storage_dir.join("2026/20035553.pdf")
    expect(summary.counts).to eq("parsed" => 1)
    expect(path.binread).to eq(pdf_bytes)
    expect(sidecar).to have_received(:parse).with(path, "ptr")
    expect(ptr.reload).to have_attributes(parse_status: "parsed", parse_error: nil,
                                          sha256: Digest::SHA256.hexdigest(pdf_bytes), pdf_path: path.relative_path_from(Rails.root).to_s)
    expect(ptr.parsed_at).to be_present
    expect(ptr.trades.sole).to have_attributes(owner: "SP", asset_type_code: "AB", tx_type: "P",
                                               tx_date: Date.new(2026, 9, 8), amount_min: 500_001, amount_max: 1_000_000)
  end

  it "keeps rows and stores reasons when the sidecar says needs_review" do
    sidecar_returns(status: "needs_review", reasons: [ "列數 1 ≠ FILING STATUS 標記數 2", "第 1 列未知金額標籤：'$15.00x'" ])
    service.call

    expect(ptr.reload.parse_status).to eq("needs_review")
    expect(ptr.parse_error).to eq("列數 1 ≠ FILING STATUS 標記數 2\n第 1 列未知金額標籤：'$15.00x'")
    expect(ptr.trades.count).to eq(1)
  end

  it "marks a scanned PDF needs_review with no rows" do
    sidecar_returns(status: "needs_review", reasons: [ "文字層幾乎為空（0 字），疑為掃描檔" ], rows: [])
    service.call

    expect(ptr.reload).to have_attributes(parse_status: "needs_review", parse_error: "文字層幾乎為空（0 字），疑為掃描檔")
    expect(ptr.trades).to be_empty
  end

  it "writes holdings for annual and amendment filings using the annual parser" do
    annual  = create(:hof_filing, doc_id: "10075701", filing_type: "amendment", year: 2026, pdf_url: pdf_url("amendment", "10075701"))
    holding = { "owner" => "JT", "asset_name" => "11 Zinfandel Lane [RP]", "ticker" => nil, "asset_type" => "RP",
                "value_label" => "$5,000,001 - $25,000,000", "value_min" => 5_000_001, "value_max" => 25_000_000 }
    WebMock.stub_request(:get, annual.pdf_url).to_return(status: 200, body: "%PDF annual")
    allow(sidecar).to receive(:parse).with(anything, "ptr").and_return(
      { "status" => "parsed", "reasons" => [], "marker_count" => 1, "rows" => [ trade_row ] }
    )
    allow(sidecar).to receive(:parse).with(anything, "annual").and_return(
      { "status" => "parsed", "reasons" => [], "marker_count" => 1, "rows" => [ holding ] }
    )

    service.call

    expect(annual.reload.holdings.sole).to have_attributes(owner: "JT", asset_type: "RP", value_min: 5_000_001)
    expect(annual.trades).to be_empty
  end

  it "only processes pending filings and reuses a stored PDF" do
    create(:hof_filing, parse_status: "parsed", pdf_url: pdf_url("ptr", "1"))
    FileUtils.mkdir_p(storage_dir.join("2026"))
    storage_dir.join("2026/20035553.pdf").binwrite(pdf_bytes)
    sidecar_returns

    summary = service.call

    expect(summary.counts).to eq("parsed" => 1)
    expect(WebMock).not_to have_requested(:get, ptr.pdf_url)
  end

  it "leaves the filing pending when the download fails" do
    WebMock.stub_request(:get, ptr.pdf_url).to_return(status: 503)
    sidecar_returns

    summary = service.call

    expect(summary.counts).to eq("pending" => 1)
    expect(summary.errors.sole).to include("20035553：", "HTTP 503")
    expect(ptr.reload).to have_attributes(parse_status: "pending", parse_error: nil)
    expect(sidecar).not_to have_received(:parse)
  end

  it "marks the filing failed when the sidecar crashes, and continues with the next one" do
    other = create(:hof_filing, doc_id: "20035554", year: 2026, pdf_url: pdf_url("ptr", "20035554"))
    WebMock.stub_request(:get, other.pdf_url).to_return(status: 200, body: "%PDF other")
    allow(sidecar).to receive(:parse).and_raise(HallOfFame::HouseParserSidecar::Error, "sidecar 結束碼 1：boom")
    allow(sidecar).to receive(:parse).with(storage_dir.join("2026/20035554.pdf"), "ptr").and_return(
      { "status" => "parsed", "reasons" => [], "marker_count" => 1, "rows" => [ trade_row ] }
    )

    summary = service.call

    expect(summary.counts).to eq("failed" => 1, "parsed" => 1)
    expect(ptr.reload).to have_attributes(parse_status: "failed", parse_error: "sidecar 結束碼 1：boom")
    expect(other.reload.parse_status).to eq("parsed")
  end

  it "isolates unexpected errors per filing (IO error, unknown filing type) and keeps going" do
    oge   = create(:hof_filing, doc_id: "20035555", filing_type: "oge_278e", year: 2026, pdf_url: pdf_url("ptr", "20035555"))
    other = create(:hof_filing, doc_id: "20035554", year: 2026, pdf_url: pdf_url("ptr", "20035554"))
    WebMock.stub_request(:get, /2003555[45]\.pdf/).to_return(status: 200, body: "%PDF other")
    sidecar_returns
    calls = 0
    allow(FileUtils).to receive(:mkdir_p).and_wrap_original do |original, *args|
      calls += 1
      raise Errno::EACCES, "storage" if calls == 1

      original.call(*args)
    end

    summary = service.call

    expect(summary.counts).to eq("failed" => 2, "parsed" => 1)
    expect(ptr.reload).to have_attributes(parse_status: "failed", parse_error: "Errno::EACCES: Permission denied - storage")
    expect(oge.reload.parse_status).to eq("failed")
    expect(oge.parse_error).to start_with("KeyError:")
    expect(other.reload.parse_status).to eq("parsed")
  end

  it "writes the PDF via a .part file and never reuses a leftover partial download" do
    FileUtils.mkdir_p(storage_dir.join("2026"))
    storage_dir.join("2026/20035553.pdf.part").binwrite("%PDF trunc")
    sidecar_returns

    service.call

    expect(storage_dir.join("2026/20035553.pdf").binread).to eq(pdf_bytes)
    expect(storage_dir.join("2026/20035553.pdf.part")).not_to exist
    expect(WebMock).to have_requested(:get, ptr.pdf_url).once
  end

  it "replaces previously written rows when a filing is parsed again" do
    create(:hof_trade, filing: ptr, asset_name: "stale")
    sidecar_returns

    service.call

    expect(ptr.trades.pluck(:asset_name)).to eq([ "REOF XXX, LLC [AB]" ])
  end

  it "re-parses a filing whose trades already have option details (P3b r1 問題 1)" do
    stale = create(:hof_trade, filing: ptr, asset_name: "MSFT option")
    create(:hof_option_detail, trade: stale, premium_ref: 12.5)
    other = create(:hof_option_detail, trade: create(:hof_trade, filing: create(:hof_filing, parse_status: "parsed")))
    sidecar_returns

    summary = service.call

    expect(summary.counts).to eq("parsed" => 1)
    expect(ptr.reload.parse_status).to eq("parsed")
    expect(HallOfFame::OptionDetail.pluck(:id)).to eq([ other.id ])
  end

  describe "with the real Python sidecar" do
    before do
      skip "名人堂 venv 未建立（lib/hall_of_fame/requirements.txt）" unless File.exist?(HallOfFame::HouseParserSidecar::PYTHON)
    end

    let(:service) { described_class.new(storage_dir: storage_dir, pause_seconds: 0) }

    it "parses the current-format Pelosi PTR fixture end to end" do
      service.call

      expect(ptr.reload.parse_status).to eq("parsed")
      expect(ptr.trades.sole).to have_attributes(owner: "SP", asset_name: "REOF XXX, LLC [AB]", tx_type: "P",
                                                 amount_label: "$500,001 - $1,000,000", amount_max: 1_000_000)
    end
  end
end
