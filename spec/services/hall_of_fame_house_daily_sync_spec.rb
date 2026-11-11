# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::HouseDailySync do
  let(:index)   { instance_double(HallOfFame::HouseIndexSync) }
  let(:parser)  { instance_double(HallOfFame::HousePdfParse) }
  let(:options) { instance_double(HallOfFame::OptionAnalysis) }
  let(:service) { described_class.new(index:, parser:, options:) }
  let(:index_run)   { create(:hof_sync_run, kind: "index", finished_at: Time.current) }
  let(:options_run) { create(:hof_sync_run, kind: "options", finished_at: Time.current) }
  let(:summary) do
    HallOfFame::HousePdfParse::Summary.new(counts: { "parsed" => 2, "failed" => 1 }, errors: [ "20001：sidecar 結束碼 1" ])
  end

  it "runs index sync, PDF parsing and option analysis in order and records a pdf_parse run" do
    order = []
    allow(index).to receive(:call) { order << :index; index_run }
    allow(parser).to receive(:call) { order << :parse; summary }
    allow(options).to receive(:call) { order << :options; options_run }

    result = service.call

    expect(order).to eq(%i[index parse options])
    expect(result).to be_ok
    parse_run = result.runs.fetch("pdf_parse")
    expect(parse_run).to have_attributes(kind: "pdf_parse", source: "house", error_count: 1)
    expect(parse_run.finished_at).to be_present
    expect(parse_run.error_log).to eq("本次處理：failed 1、parsed 2\n20001：sidecar 結束碼 1")
    expect(result.runs.values_at("index", "options")).to eq([ index_run, options_run ])
  end

  it "keeps going when a step raises and reports the failure" do
    allow(index).to receive(:call).and_raise(HallOfFame::HouseIndexFetcher::Error, "HTTP 503")
    allow(parser).to receive(:call).and_raise(IOError, "disk full")
    allow(options).to receive(:call).and_return(options_run)

    result = service.call

    expect(result).not_to be_ok
    expect(result.failures).to eq([ "index：HallOfFame::HouseIndexFetcher::Error: HTTP 503", "pdf_parse：IOError: disk full" ])
    expect(options).to have_received(:call)
    expect(HallOfFame::SyncRun.find_by!(kind: "pdf_parse"))
      .to have_attributes(error_count: 1, error_log: "IOError: disk full", finished_at: be_present)
  end

  it "notes when there is nothing pending" do
    allow(index).to receive(:call).and_return(index_run)
    allow(parser).to receive(:call).and_return(HallOfFame::HousePdfParse::Summary.new(counts: {}, errors: []))
    allow(options).to receive(:call).and_return(options_run)

    expect(service.call.runs.fetch("pdf_parse")).to have_attributes(error_count: 0, error_log: "本次處理：無 pending")
  end
end
