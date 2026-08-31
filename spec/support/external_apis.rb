# frozen_string_literal: true

require "webmock/rspec"

# 測試中一律不對外連線。
#
# ── 為什麼 ────────────────────────────────────────────────────────────
# 在這之前，六支 request spec（absolute_timeout / idle_timeout / auth_gate /
# account_security / admin_users / technical_dashboards）會渲染 /momentum 這類
# 真實頁面，而那條路徑會呼叫 VixService、FinnhubService#quote×N、
# YahooFinanceService#chart×N。這些呼叫包在 Rails.cache.fetch 裡，但 test 環境
# 的 cache_store 是 :null_store——快取永遠不命中，每次都真的出網。
#
# absolute_timeout_spec 更是 `25.times { travel 1.hour; get "/momentum" }`，
# 單支就要 138 秒，而且任何一次 API 抖動或限流都會讓斷言落空
# （2026-08-30 實際遇過一次偶發失敗）。
#
# 那六支想驗的是登入逾時與權限閘門，跟 Finnhub 報價毫無關係，不該被綁在一起。
#
# ── 這裡做什麼 ────────────────────────────────────────────────────────
# 1. 封鎖所有對外連線：漏掉的請求會**立刻拋例外並指名是哪一行**，
#    而不是安靜地送出去。
# 2. 為每個外部服務準備一份「形狀正確、數值固定」的預設回應，讓頁面渲染得出來。
#
# 個別 spec 需要特定數值時，照常用 stub_request 或既有的 allow(...).to receive
# 覆寫——後宣告的優先。
WebMock.disable_net_connect!(allow_localhost: true)

module ExternalApiStubs
  # 形狀取自各 service 實際解析的欄位，不是憑印象寫的：
  #   FinnhubService#quote      → c/d/dp/h/l/o/pc
  #   YahooFinanceService#chart → chart.result[0].meta / .indicators.quote[0]
  def self.stub_all
    stub_finnhub
    stub_yahoo
    stub_misc
  end

  # 注意順序：WebMock 是「後註冊者優先」，所以 catch-all 必須先註冊，
  # 具體端點後註冊才蓋得過它。反過來寫的話所有請求都會拿到 catch-all 的
  # 空物件——服務會優雅降級、測試照樣綠，但樁形同虛設（實際踩過）。
  def self.stub_finnhub
    # 兜底：沒列到的端點回空物件，而不是放行出網
    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/}).to_return(**json({}))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/quote})
           .to_return(**json(c: 100.0, d: 1.5, dp: 1.52, h: 101.0, l: 99.0, o: 99.5, pc: 98.5))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/stock/market-status})
           .to_return(**json(exchange: "US", isOpen: false, session: "closed"))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/calendar/earnings})
           .to_return(**json(earningsCalendar: []))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/(news|company-news)})
           .to_return(**json([]))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/stock/profile2})
           .to_return(**json(name: "Test Corp", ticker: "TEST", finnhubIndustry: "Technology"))

    WebMock.stub_request(:get, %r{\Ahttps://finnhub\.io/api/v1/stock/metric})
           .to_return(**json(metric: {}))
  end

  def self.stub_yahoo
    # 同樣先註冊兜底，具體端點在後（見 stub_finnhub 的說明）
    WebMock.stub_request(:get, %r{\Ahttps://query[12]\.finance\.yahoo\.com/}).to_return(**json({}))
    WebMock.stub_request(:get, %r{\Ahttps://finance\.yahoo\.com/}).to_return(**json({}))

    chart = {
      chart: {
        result: [ {
          # meta 的欄位名取自 YahooFinanceService#chart 實際讀的鍵：
          # fiftyTwoWeekHigh/Low → high_52w/low_52w，regularMarketVolume → volume
          meta: {
            regularMarketPrice: 100.0, previousClose: 98.5, chartPreviousClose: 98.5,
            fiftyTwoWeekHigh: 120.0, fiftyTwoWeekLow: 80.0, regularMarketVolume: 1_000_000
          },
          timestamp:  [ 1_700_000_000 ],
          indicators: { quote: [ { open: [ 99.5 ], high: [ 101.0 ], low: [ 99.0 ],
                                   close: [ 100.0 ], volume: [ 1_000_000 ] } ] }
        } ],
        error: nil
      }
    }
    WebMock.stub_request(:get, %r{\Ahttps://query[12]\.finance\.yahoo\.com/v8/finance/chart})
           .to_return(**json(chart))

    WebMock.stub_request(:get, %r{\Ahttps://query[12]\.finance\.yahoo\.com/v\d+/finance/quoteSummary})
           .to_return(**json(quoteSummary: { result: [ {} ], error: nil }))
  end

  def self.stub_misc
    # 這些在單元測試裡通常已有自己的樁；這裡只是兜底，免得漏網請求真的出去。
    WebMock.stub_request(:any, %r{\Ahttps://api\.groq\.com/}).to_return(**json(choices: []))
    WebMock.stub_request(:any, %r{\Ahttps://api\.telegram\.org/}).to_return(**json(ok: true, result: []))
    WebMock.stub_request(:get, %r{\Ahttps://efts\.sec\.gov/}).to_return(**json(hits: { hits: [] }))
    WebMock.stub_request(:get, %r{\Ahttps://(api\.exchangerate-api\.com|open\.er-api\.com)/})
           .to_return(**json(rates: { "TWD" => 32.0 }, result: "success"))
    WebMock.stub_request(:get, %r{\Ahttps://api\.mymemory\.translated\.net/})
           .to_return(**json(responseData: { translatedText: "" }))
  end

  def self.json(body)
    { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end
end

RSpec.configure do |config|
  # 每個 example 前重新掛上——WebMock 會在 example 之間重置註冊的樁。
  config.before { ExternalApiStubs.stub_all }
end
