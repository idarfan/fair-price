# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::PeerMultipleService do
  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  before { allow(ENV).to receive(:fetch).with("FINNHUB_API_KEY").and_return("test_key") }

  def stub_peers(symbol, list)
    stub_request(:get, "https://finnhub.io/api/v1/stock/peers")
      .with(query: hash_including(symbol: symbol))
      .to_return(status: 200, body: list.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_metric(symbol, pe)
    stub_request(:get, "https://finnhub.io/api/v1/stock/metric")
      .with(query: hash_including(symbol: symbol))
      .to_return(status: 200, body: { metric: { "peTTM" => pe } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "回傳同業本益比的四分位區間" do
    stub_peers("MRVL", %w[MRVL AVGO QCOM ADI NVDA])
    { "AVGO" => 40.0, "QCOM" => 20.0, "ADI" => 60.0, "NVDA" => 80.0 }.each { |s, v| stub_metric(s, v) }

    result = described_class.call("MRVL")
    expect(result).to be_available
    expect(result.low).to be_within(0.01).of(35.0)
    expect(result.high).to be_within(0.01).of(65.0)
    expect(result.sample_size).to eq(4)
  end

  # 拿自己的本益比當「同業平均」是循環論證。
  it "把自己從同業清單中排除" do
    stub_peers("MRVL", %w[MRVL AVGO QCOM ADI])
    { "AVGO" => 40.0, "QCOM" => 20.0, "ADI" => 60.0 }.each { |s, v| stub_metric(s, v) }
    stub_metric("MRVL", 999.0)

    expect(described_class.call("MRVL").peers).not_to include("MRVL")
  end

  it "樣本少於 3 檔時視為算不出來，回傳不可用" do
    stub_peers("MRVL", %w[AVGO QCOM])
    stub_metric("AVGO", 40.0)
    stub_metric("QCOM", nil)

    expect(described_class.call("MRVL")).not_to be_available
  end

  it "同業清單抓不到時回傳不可用，不拋例外" do
    stub_request(:get, "https://finnhub.io/api/v1/stock/peers")
      .with(query: hash_including(symbol: "MRVL")).to_return(status: 500, body: "")

    result = nil
    expect { result = described_class.call("MRVL") }.not_to raise_error
    expect(result).not_to be_available
  end

  it "負本益比（虧損同業）不計入樣本" do
    stub_peers("MRVL", %w[AVGO QCOM ADI NVDA])
    { "AVGO" => 40.0, "QCOM" => -5.0, "ADI" => 60.0, "NVDA" => 50.0 }.each { |s, v| stub_metric(s, v) }

    expect(described_class.call("MRVL").sample_size).to eq(3)
  end

  it "第二次呼叫命中快取，不再打上游" do
    peers = stub_peers("MRVL", %w[AVGO QCOM ADI])
    { "AVGO" => 40.0, "QCOM" => 20.0, "ADI" => 60.0 }.each { |s, v| stub_metric(s, v) }

    described_class.call("MRVL")
    described_class.call("MRVL")
    expect(peers).to have_been_requested.once
  end
end
