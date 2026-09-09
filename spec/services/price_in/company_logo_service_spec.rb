# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::CompanyLogoService do
  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  before { allow(ENV).to receive(:fetch).with("FINNHUB_API_KEY").and_return("test_key") }

  def stub_profile(symbol, body:, status: 200)
    stub_request(:get, "https://finnhub.io/api/v1/stock/profile2")
      .with(query: hash_including(symbol: symbol))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "回傳 logo URL 與公司名稱" do
    stub_profile("SHOP", body: { logo: "https://example.test/SHOP.png", name: "Shopify Inc" })

    result = described_class.call("SHOP")
    expect(result).to be_logo
    expect(result.logo_url).to eq("https://example.test/SHOP.png")
    expect(result.name).to eq("Shopify Inc")
  end

  it "第二次呼叫命中快取，不再打上游" do
    request = stub_profile("SHOP", body: { logo: "https://example.test/SHOP.png", name: "Shopify Inc" })

    described_class.call("SHOP")
    described_class.call("SHOP")
    expect(request).to have_been_requested.once
  end

  # Finnhub 對部分 ETF 會回 logo: ""，空字串不該被當成有效的圖片網址。
  it "logo 為空字串時視為沒有" do
    stub_profile("SPY", body: { logo: "", name: "SPDR S&P 500" })
    expect(described_class.call("SPY")).not_to be_logo
  end

  it "上游失敗時回傳空 Profile，不拋例外" do
    stub_profile("NOPE", body: {}, status: 500)

    result = nil
    expect { result = described_class.call("NOPE") }.not_to raise_error
    expect(result).not_to be_logo
  end

  it "空代號直接回空，不打上游" do
    expect(described_class.call("")).not_to be_logo
    expect(a_request(:get, /finnhub/)).not_to have_been_made
  end

  # 快取存的是 Hash 不是 Data：Data 的 Marshal 綁死欄位數量。
  it "快取內容為 Hash" do
    stub_profile("SHOP", body: { logo: "https://example.test/SHOP.png", name: "Shopify Inc" })
    described_class.call("SHOP")

    expect(Rails.cache.read("price_in:logo:v1:SHOP")).to be_a(Hash)
  end
end
