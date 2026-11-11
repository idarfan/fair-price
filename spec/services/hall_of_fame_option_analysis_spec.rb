# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OptionAnalysis do
  let(:reference) { instance_double(HallOfFame::PremiumReference) }
  let(:service)   { described_class.new(reference:) }
  let(:filing)    { create(:hof_filing, parse_status: "parsed") }
  let(:ok_ref) do
    HallOfFame::PremiumReference::Ref.new(status: :ok, source: "barchart_dom", value: BigDecimal("12.50"),
                                          underlying: BigDecimal("400"), note: "Barchart DOM url 收盤 12.5")
  end
  let(:offline_ref) do
    HallOfFame::PremiumReference::Ref.new(status: :cdp_offline, source: nil, value: nil, underlying: nil, note: "CDP 未連線，待重試")
  end

  def option_trade(description, amount_min:, amount_max:, ticker: "MSFT", code: "OP", tx_date: Date.new(2026, 8, 14))
    create(:hof_trade, filing:, ticker:, asset_type_code: code, description:, tx_date:, asset_name: "#{ticker} option",
                       amount_min:, amount_max:, amount_label: "x")
  end

  before { allow(service).to receive(:cdp_online?).and_return(true) }

  it "estimates the contract range from premium_ref (B path: 12.50, $250,001–$500,000 → 201～400)" do
    trade = option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 250_001, amount_max: 500_000)
    allow(reference).to receive(:resolve).and_return(ok_ref)

    run = service.call

    expect(trade.reload.option_detail).to have_attributes(
      option_right: "call", strike: 340, expiration: Date.new(2026, 10, 16), contracts_stated: nil,
      premium_source: "barchart_dom", premium_ref: BigDecimal("12.5"), underlying_close: 400,
      contracts_est_min: 201, contracts_est_max: 400
    )
    expect(trade.option_detail.calc_note).to include("口數 = 金額區間 ÷ (12.5 × 100) = 201～400")
    expect(run).to have_attributes(kind: "options", source: "house", error_count: 0)
    expect(run.finished_at).to be_present
    expect(filing.reload.parse_status).to eq("parsed")
  end

  it "derives the implied premium from stated contracts and cross-checks the market price (A path)" do
    trade = option_trade("Purchased 200 call options with a strike price of $50 and an expiration date of 3/19/27.",
                         amount_min: 1_000_001, amount_max: 5_000_000, ticker: "INTC")
    allow(reference).to receive(:resolve).and_return(ok_ref)

    service.call

    detail = trade.reload.option_detail
    expect(detail).to have_attributes(premium_source: "stated_contracts", contracts_stated: 200,
                                      premium_implied_min: BigDecimal("50.0001"), premium_implied_max: BigDecimal("250"),
                                      premium_ref: BigDecimal("12.5"))
    expect(detail.calc_note).to include("申報口數與市價不符")
  end

  it "keeps rows needing premium_ref in needs_review when CDP is offline and logs the offline message" do
    trade = option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 250_001, amount_max: 500_000)
    allow(service).to receive(:cdp_online?).and_return(false)
    allow(reference).to receive(:resolve).and_return(offline_ref)

    run = service.call

    expect(reference).to have_received(:resolve).with(hash_including(cdp_online: false))
    expect(trade.reload.option_detail).to have_attributes(premium_ref: nil, premium_source: nil, contracts_est_min: nil)
    expect(trade.option_detail.calc_note).to include("CDP 未連線")
    expect(filing.reload.parse_status).to eq("needs_review")
    expect(filing.parse_error).to include("[期權] MSFT option（2026-08-14）：CDP 未連線，待重試")
    expect(run.error_log).to include(CdpPrecheckable::CDP_OFFLINE_MESSAGE)
  end

  it "reports an offline CDP within the 2-second precheck budget" do
    WebMock.stub_request(:get, CdpPrecheckable::CDP_VERSION_URL).to_timeout
    real = described_class.new(reference:)
    allow(reference).to receive(:resolve).and_return(offline_ref)
    option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 250_001, amount_max: 500_000)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run = real.call

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < CdpPrecheckable::CDP_PRECHECK_TIMEOUT
    expect(CdpPrecheckable::CDP_PRECHECK_TIMEOUT).to eq(2)
    expect(run.error_log).to start_with(CdpPrecheckable::CDP_OFFLINE_MESSAGE)
  end

  it "retries pending rows on the next run and restores the filing status" do
    trade = option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 250_001, amount_max: 500_000)
    filing.update!(parse_error: "第 3 列未知金額標籤：'x'", parse_status: "needs_review")
    allow(reference).to receive(:resolve).and_return(offline_ref, ok_ref)

    service.call
    service.call

    expect(trade.reload.option_detail.contracts_est_min).to eq(201)
    expect(filing.reload).to have_attributes(parse_status: "needs_review", parse_error: "第 3 列未知金額標籤：'x'")
    expect(HallOfFame::OptionDetail.count).to eq(1)
  end

  it "records exercised options without deriving a premium" do
    trade = option_trade("Exercised 50 call options purchased 1/14/25 (5,000 shares) at a strike price of $20 " \
                         "with an expiration date of 1/16/26.", amount_min: 50_001, amount_max: 100_000, code: "ST", ticker: "TEM")
    allow(reference).to receive(:resolve)

    service.call

    expect(reference).not_to have_received(:resolve)
    expect(trade.reload.option_detail).to have_attributes(contracts_stated: 50, strike: 20, premium_source: nil,
                                                          premium_implied_min: nil, premium_ref: nil)
    expect(trade.option_detail.calc_note).to start_with("履約交易")
    expect(filing.reload.parse_status).to eq("parsed")
  end

  it "does not rewrite an unchanged detail on later runs (P3b r1 質詢 2)" do
    trade = option_trade("Exercised 50 call options purchased 1/14/25 (5,000 shares) at a strike price of $20 " \
                         "with an expiration date of 1/16/26.", amount_min: 50_001, amount_max: 100_000, code: "ST", ticker: "TEM")
    service.call
    first = trade.reload.option_detail.updated_at

    travel(1.day) { service.call }

    expect(trade.option_detail.reload.updated_at).to eq(first)
  end

  it "marks an unparseable option description needs_review without guessing values" do
    trade = option_trade("10 puts at $22.00", amount_min: 1001, amount_max: 15_000, code: "OP")
    allow(reference).to receive(:resolve)

    service.call

    expect(trade.reload.option_detail).to have_attributes(option_right: nil, strike: nil, premium_ref: nil)
    expect(filing.reload.parse_status).to eq("needs_review")
    expect(filing.parse_error).to include("期權描述無法解析")
  end

  it "skips non-option trades and rows that already have a premium_ref" do
    create(:hof_trade, filing:, asset_type_code: "ST", description: "Purchased 10,000 shares.")
    done = option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 1, amount_max: 2)
    create(:hof_option_detail, trade: done, premium_ref: 3)
    allow(reference).to receive(:resolve)

    service.call

    expect(reference).not_to have_received(:resolve)
    expect(HallOfFame::OptionDetail.count).to eq(1)
  end

  it "finishes the run with the exception message when analysis raises" do
    option_trade("Call options; Strike price $340; Expires 10/16/2026", amount_min: 250_001, amount_max: 500_000)
    allow(reference).to receive(:resolve).and_raise(Timeout::Error, "Barchart sidecar timeout")

    expect { service.call }.to raise_error(Timeout::Error)

    expect(HallOfFame::SyncRun.find_by!(kind: "options"))
      .to have_attributes(error_count: 1, error_log: "Timeout::Error: Barchart sidecar timeout", finished_at: be_present)
  end

  it "keeps P2 conditional-request validators intact (options runs are not index runs)" do
    url = HallOfFame::HouseIndexSync.zip_url(2026)
    create(:hof_sync_run, kind: "index", finished_at: 1.hour.ago, started_at: 2.hours.ago,
                          http_validators: { url => { "etag" => '"x"' } })
    service.call
    stub = WebMock.stub_request(:get, url).with(headers: { "If-None-Match" => '"x"' }).to_return(status: 304)

    HallOfFame::HouseIndexSync.new(years: [ 2026 ]).call

    expect(stub).to have_been_requested
  end

  describe "with the Pelosi PTR fixture 20034836", :aggregate_failures do
    before do
      skip "名人堂 venv 未建立" unless File.exist?(HallOfFame::HouseParserSidecar::PYTHON)
      storage = Rails.root.join("tmp/spec_hof_options")
      ptr = create(:hof_filing, doc_id: "20034836", year: 2026, pdf_url: HallOfFame::HouseIndexSync.pdf_url("ptr", 2026, "20034836"))
      WebMock.stub_request(:get, ptr.pdf_url).to_return(body: Rails.root.join("spec/fixtures/hall_of_fame/20034836.pdf").binread)
      HallOfFame::HousePdfParse.new(storage_dir: storage, pause_seconds: 0).call
      FileUtils.rm_rf(storage)
      allow(reference).to receive(:resolve).and_return(ok_ref)
    end

    it "derives INTC 50.00～250.00 and UBER 25.00～50.00 from 200 stated contracts" do
      service.call

      intc, uber = %w[INTC UBER].map { |t| HallOfFame::Trade.find_by!(ticker: t).option_detail }
      expect(intc).to have_attributes(option_right: "call", strike: 50, expiration: Date.new(2027, 3, 19), contracts_stated: 200,
                                      premium_source: "stated_contracts", premium_implied_max: BigDecimal("250"))
      expect(intc.premium_implied_min).to be_within(0.01).of(50)
      expect(uber).to have_attributes(strike: 50, expiration: Date.new(2027, 3, 19), contracts_stated: 200,
                                      premium_implied_max: BigDecimal("50"))
      expect(uber.premium_implied_min).to be_within(0.01).of(25)
    end
  end
end
