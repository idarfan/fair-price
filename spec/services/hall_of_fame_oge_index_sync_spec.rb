# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OgeIndexSync do
  let(:fixtures) { Rails.root.join("spec/fixtures/hall_of_fame/oge") }
  let(:gate_url) { described_class::GATE_URL }
  let(:validators) { { "ETag" => 'W/"gate-1"', "Last-Modified" => "Sun, 18 Oct 2026 13:33:32 GMT" } }
  let!(:trump)  { create(:hof_official, slug: "trump", last_name: "Trump", first_name: "Donald", category: "executive", source: "oge") }
  let!(:burgum) { create(:hof_official, slug: "burgum", last_name: "Burgum", first_name: "Doug", category: "executive", source: "oge") }

  def stub_gate(status: 200, headers: validators)
    WebMock.stub_request(:get, gate_url).to_return(status:, body: status == 200 ? "{}" : "", headers:)
  end

  def stub_api(last_name, body)
    WebMock.stub_request(:get, described_class::API_URL)
           .with(query: hash_including("search" => { "value" => last_name }))
           .to_return(status: 200, body: body.is_a?(String) ? body : body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def record(name:, type:, date: "2026-09-28T00:00:00")
    { "name" => name, "title" => "Secretary", "agency" => "Department of Commerce", "level" => "n/a", "type" => type, "docDate" => date, "amended" => "" }
  end

  before do
    stub_api("Trump", fixtures.join("api_trump.json").read)
    stub_api("Burgum", fixtures.join("api_burgum.json").read)
  end

  it "upserts 278e／278-T filings with UNID doc_id and the OGE PDF URL, ignoring other documents" do
    stub_gate

    run = described_class.new.call

    trump_rows = HallOfFame::Filing.where(official: trump).order(:filing_date).pluck(:doc_id, :filing_type, :year, :filing_date)
    expect(trump_rows).to eq([
      [ "6E78B163F816EF6A852586630075291D", "oge_278e", 2021, Date.new(2021, 1, 20) ],
      [ "4EC9A8E6DD078F2985258CA9002C9377", "oge_278e", 2025, Date.new(2025, 6, 14) ],
      [ "18353894FE440B3685258D430031A337", "oge_278t", 2025, Date.new(2025, 11, 15) ]
    ])
    expect(HallOfFame::Filing.find_by!(doc_id: "4EC9A8E6DD078F2985258CA9002C9377").pdf_url)
      .to eq("https://extapps2.oge.gov/201/Presiden.nsf/PAS+Index/4EC9A8E6DD078F2985258CA9002C9377/$FILE/Trump%2C%20Donald%20J.%202025%20Annual%20278.pdf")
    # Burgum：Nominee 278 1 份＋278 Transaction 6 份；Ethics Agreement／Certification／候選人報告不收
    expect(HallOfFame::Filing.where(official: burgum).group(:filing_type).count).to eq("oge_278e" => 1, "oge_278t" => 6)
    expect(HallOfFame::Filing.where(source: "oge").pluck(:parse_status).uniq).to eq([ "pending" ])
    expect(run).to have_attributes(source: "oge", kind: "index", new_filings_count: 10, error_count: 0,
                                   http_validators: { gate_url => { "etag" => 'W/"gate-1"', "last_modified" => "Sun, 18 Oct 2026 13:33:32 GMT" } })
  end

  it "stops at the gate on 304 without calling the API, keeping the validators" do
    stub_gate
    described_class.new.call
    WebMock.reset_executed_requests!
    gate304 = WebMock.stub_request(:get, gate_url).with(headers: { "If-None-Match" => 'W/"gate-1"' }).to_return(status: 304)

    run = described_class.new.call

    expect(gate304).to have_been_requested
    expect(WebMock).not_to have_requested(:get, described_class::API_URL).with(query: hash_including({}))
    expect(run).to have_attributes(new_filings_count: 0, http_validators: { gate_url => hash_including("etag" => 'W/"gate-1"') })
  end

  it "counts zero new filings when the index changed but the same reports come back" do
    stub_gate
    described_class.new.call
    stub_gate(headers: { "ETag" => 'W/"gate-2"' })

    expect(described_class.new.call.new_filings_count).to eq(0)
    expect(HallOfFame::Filing.where(source: "oge").count).to eq(10)
  end

  it "skips 278 reports without an online PDF and logs a warning" do
    lutnick = create(:hof_official, slug: "lutnick", last_name: "Lutnick", first_name: "Howard", category: "executive", source: "oge")
    request_only = "Annual (2026) (<a href='https://extapps2.oge.gov/201/Presiden.nsf/201%20Request?OpenForm&Filer=Lutnick'>Request this Document</a>)"
    stub_api("Lutnick", { "recordsFiltered" => 1, "data" => [ record(name: "Lutnick, Howard", type: request_only) ] })
    stub_gate

    run = described_class.new.call

    expect(HallOfFame::Filing.where(official: lutnick)).to be_empty
    expect(run.error_log).to include("警示：lutnick Annual (2026)（2026-09-28）沒有線上 PDF，需書面申請，未寫入")
    expect(run.error_count).to eq(0)
  end

  it "pages through the API until recordsFiltered is reached" do
    pdf = ->(unid) { "<a href='#{described_class::BASE}/PAS+Index/#{unid}/$FILE/x.pdf'>278 Transaction</a>" }
    first  = Array.new(100) { |i| record(name: "Burgum, Douglas J", type: pdf.call(format("%032X", i))) }
    second = [ record(name: "Burgum, Douglas J", type: pdf.call(format("%032X", 100))) ]
    WebMock.stub_request(:get, described_class::API_URL).with(query: hash_including("search" => { "value" => "Burgum" }, "start" => "0"))
           .to_return(body: { "recordsFiltered" => 101, "data" => first }.to_json)
    WebMock.stub_request(:get, described_class::API_URL).with(query: hash_including("search" => { "value" => "Burgum" }, "start" => "100"))
           .to_return(body: { "recordsFiltered" => 101, "data" => second }.to_json)
    stub_gate

    described_class.new.call

    expect(HallOfFame::Filing.where(official: burgum).count).to eq(101)
  end

  it "records a per-official API failure and still syncs the others" do
    WebMock.stub_request(:get, described_class::API_URL).with(query: hash_including("search" => { "value" => "Burgum" })).to_return(status: 503)
    stub_gate

    run = described_class.new.call

    expect(HallOfFame::Filing.where(official: trump).count).to eq(3)
    expect(run.error_count).to eq(1)
    expect(run.error_log).to include("錯誤：burgum 查詢失敗：", "HTTP 503")
    # Q1 r1 問題 1：有人失敗時不存關卡的新 validators，下一次一定重查
    expect(run.http_validators).to eq({})
  end

  it "re-queries a failed official on the next run instead of stopping at a 304 gate (Q1 r1 問題 1)" do
    stub_gate(headers: { "ETag" => 'W/"g0"' })
    described_class.new.call # 成功的一輪，留下 W/"g0"
    WebMock.reset_executed_requests!
    stub_gate(headers: { "ETag" => 'W/"g1"' })
    burgum_api = WebMock.stub_request(:get, described_class::API_URL)
                        .with(query: hash_including("search" => { "value" => "Burgum" }))
                        .to_return({ status: 503 }, { status: 200, body: fixtures.join("api_burgum.json").read })
    HallOfFame::Filing.where(official: burgum).delete_all

    failed = described_class.new.call
    WebMock.stub_request(:get, gate_url).with(headers: { "If-None-Match" => 'W/"g1"' }).to_return(status: 304)
    retried = described_class.new.call

    expect(failed).to have_attributes(error_count: 1, http_validators: { gate_url => hash_including("etag" => 'W/"g0"') })
    expect(retried).to have_attributes(error_count: 0, new_filings_count: 7)
    expect(burgum_api).to have_been_requested.twice
    expect(HallOfFame::Filing.where(official: burgum).count).to eq(7)
  end

  it "does not match a different person with the same last name" do
    stub_api("Trump", { "recordsFiltered" => 1, "data" => [
      record(name: "Trump, Ivanka", type: "<a href='#{described_class::BASE}/PAS+Index/#{'A' * 32}/$FILE/x.pdf'>Termination</a>")
    ] })
    stub_gate

    described_class.new.call

    expect(HallOfFame::Filing.where(official: trump)).to be_empty
  end
end
