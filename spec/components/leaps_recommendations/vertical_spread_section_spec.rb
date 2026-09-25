# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P4：垂直價差區塊的 4 種狀態。數字一律由 LeapsVerticalSpreadService
# 算好（這裡用 stub 的 fetcher 跑真的 service），元件只負責呈現。
RSpec.describe LeapsRecommendations::VerticalSpreadSection do
  def d(value) = value.nil? ? nil : BigDecimal(value.to_s)

  def quote(strike, bid: nil, ask: nil, last: nil, delta: nil)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: d(last), delta: d(delta) }
  end

  let(:spot) { d("139.54") }
  let(:chain) do
    { status: :ok, symbol: "ORCL", spot: spot, expirations: [
      { expiry: "2027-10-15-m", dte: 385, fetched_at: Time.zone.parse("2026-09-25 13:44 UTC"),
        calls: [ quote(100, bid: 52, ask: 54, delta: 0.81), quote(120, bid: 30, ask: 32, delta: 0.6),
                 quote(150, bid: 9, ask: 11, delta: 0.45), quote(170, bid: 4, ask: 6, delta: 0.31) ] },
      { expiry: "2029-01-19-m", dte: 847, fetched_at: Time.zone.parse("2026-09-25 13:44 UTC"),
        calls: [ quote(100, bid: 65, ask: 68, delta: 0.8), quote(200, bid: 0, ask: 0, last: 21, delta: 0.3) ] }
    ] }
  end

  def outcome_for(result, long_strike: "100", **params)
    allow(LeapsRankingService).to receive(:new).and_return(instance_double(LeapsRankingService, call: []))
    fetcher = instance_double(LeapsCallChainFetcher, call: result)
    LeapsVerticalSpreadService.new(ticker: "ORCL", long_strike: long_strike, fetcher: fetcher, **params).call
  end

  def render_html(**kwargs)
    Nokogiri::HTML(described_class.new(symbol: "ORCL", user_strike: "100", **kwargs).call)
  end

  describe "結果" do
    let(:html) { render_html(outcome: outcome_for(chain, expiry: "2027-10-15-m")) }

    it "有 2 個 select；買入腳每個選項的履約價都是 K_L；賣出腳都 > max(K_L, 現價)" do
      expect(html.css("select").size).to eq(2)

      long_strikes = html.css('select[name="expiry"] option').map { |o| o.text.split("｜")[1] }
      expect(long_strikes).to all(eq("100.00"))

      short_strikes = html.css('select[name="short_strike"] option').map { |o| d(o["value"]) }
      expect(short_strikes).to eq([ d(150), d(170) ])
      expect(short_strikes).to all(be > [ d(100), spot ].max)
    end

    it "結果卡依規格順序：實付淨成本、最大獲利、損益兩平、最大虧損、風險報酬比、價差寬度" do
      labels = html.css(".grid > div > p:first-child").map(&:text)
      expect(labels).to eq(%w[實付淨成本 最大獲利 損益兩平 最大虧損 風險報酬比 價差寬度])
    end

    it "標題列顯示台北時間的報價時間，並有固定提示" do
      expect(html.text).to include("報價時間：2026-09-25 21:44（台北時間）")
      expect(html.text).to include(described_class::NOTE)
    end

    it "兩腳都有買賣價時不出現盤後標籤" do
      expect(html.text).not_to include("盤後參考價")
    end
  end

  it "盤後參考價：黃色標籤寫出是哪一腳，選項旁也標註" do
    html = render_html(outcome: outcome_for(chain, expiry: "2029-01-19-m", short_strike: "200"))

    expect(html.at_css(".bg-yellow-50").text).to include(described_class::AFTER_HOURS_BADGE, "賣出腳")
    expect(html.at_css('select[name="short_strike"] option[selected]').text).to include("（盤後參考價）")
  end

  it "載入中：進度條與進度文字，沒有任何計算數字" do
    html = render_html(state: :loading)

    expect(html.at_css("[data-vs-progress]")).to be_present
    expect(html.at_css("[data-vs-progress-text]").text).to include("讀取 Barchart 報價中")
    expect(html.text).not_to include("實付淨成本")
  end

  it "錯誤（功能定義 6）：紅字訊息，沒有任何計算數字" do
    html = render_html(outcome: outcome_for(chain, long_strike: "101.37"))

    expect(html.at_css(".bg-red-50").text).to include("ORCL 的 LEAPS 中查無履約價 101.37")
    expect(html.text).not_to include("實付淨成本")
    expect(html.at_css("[data-vs-retry]")).to be_nil
  end

  it "讀取失敗：紅字加重試按鈕，沒有任何計算數字" do
    html = render_html(outcome: outcome_for({ status: :error, code: :stalled,
                                              message: "讀取 2028-01-21 chain 超過 30 秒沒有回應" }))

    expect(html.at_css(".bg-red-50").text).to include("Barchart 讀取失敗：讀取 2028-01-21 chain 超過 30 秒沒有回應")
    expect(html.at_css("[data-vs-retry]").text).to eq("重試")
    expect(html.text).not_to include("實付淨成本")
  end

  it "CDP 離線：顯示訊息與重試" do
    html = render_html(state: :cdp_offline, message: CdpPrecheckable::CDP_OFFLINE_MESSAGE)

    expect(html.text).to include("CDP 未連線")
    expect(html.at_css("[data-vs-retry]")).to be_present
  end
end
