# frozen_string_literal: true

require "rails_helper"

# spec/support/external_apis.rb 自己的守門測試。
#
# 為什麼需要：那份設定壞掉時**不會有任何測試變紅**。
# 實際踩過的例子——WebMock 是「後註冊者優先」，而 catch-all 原本寫在最後，
# 於是它蓋掉了所有具體端點的樁。每個請求都拿到空物件 `{}`，服務優雅降級、
# 頁面照樣渲染得出來、719 個測試全綠，但樁完全沒有在提供資料。
#
# 沒有這支測試，那個狀態可以無限期存在下去。
RSpec.describe "外部 API 攔截設定" do
  it "未註冊的外部主機會被擋下" do
    expect { HTTParty.get("https://example.invalid/should-be-blocked") }
      .to raise_error(WebMock::NetConnectNotAllowedError)
  end

  it "localhost 仍然放行（request spec 需要）" do
    expect(WebMock::Config.instance.allow_localhost).to be(true)
  end

  # 以下三項確認「具體端點的樁真的蓋過 catch-all」。
  # 若有人把 catch-all 挪到後面註冊，這三項會立刻紅。
  it "finnhub quote 回的是樁的數值，不是 catch-all 的空物件" do
    body = HTTParty.get("https://finnhub.io/api/v1/quote?symbol=AAPL").parsed_response

    expect(body["c"]).to eq(100.0)
    expect(body["pc"]).to eq(98.5)
  end

  it "yahoo chart 回的是完整結構，不是 catch-all 的空物件" do
    body = HTTParty.get("https://query1.finance.yahoo.com/v8/finance/chart/AAPL").parsed_response

    expect(body.dig("chart", "result", 0, "meta", "regularMarketPrice")).to eq(100.0)
    expect(body.dig("chart", "result", 0, "indicators", "quote", 0, "close")).to eq([ 100.0 ])
  end

  it "沒列到的 finnhub 端點會落到 catch-all（而不是出網）" do
    body = HTTParty.get("https://finnhub.io/api/v1/some/unlisted/endpoint").parsed_response

    expect(body).to eq({})
  end

  # 這一項確認服務層真的走得通——形狀對不對，用實際的 service 而不是原始 HTTP 驗。
  it "FinnhubService#quote 解析得出樁的資料" do
    expect(FinnhubService.new.quote("AAPL")["c"]).to eq(100.0)
  end

  it "YahooFinanceService#chart 解析得出樁的資料" do
    result = YahooFinanceService.new.chart("AAPL", range: "1d", interval: "1d")

    # 這四個欄位分別來自 meta 與 indicators.quote 兩處，一起驗才能確認
    # 樁的巢狀結構整段都對（只驗一個欄位時，另一半壞掉不會被發現）。
    expect(result[:volume]).to eq(1_000_000)      # meta.regularMarketVolume
    expect(result[:high_52w]).to eq(120.0)        # meta.fiftyTwoWeekHigh
    expect(result[:change_pct]).to eq(1.52)       # meta 算出來的
    expect(result[:closes]).to eq([ 100.0 ])      # indicators.quote[0].close
  end
end
