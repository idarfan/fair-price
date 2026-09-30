# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P3。sidecar 一律 stub（LeapsCallChainFetcher 換成替身），不連 Barchart。
RSpec.describe "LEAPS 垂直價差", type: :request do
  def d(value) = value.nil? ? nil : BigDecimal(value.to_s)

  def quote(strike, bid: nil, ask: nil, last: nil, delta: nil)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: d(last), delta: d(delta) }
  end

  let(:exp_near) { "2027-10-15-m" }
  let(:exp_far)  { "2029-01-19-m" }
  let(:chain) do
    { status: :ok, symbol: "ORCL", spot: d("139.54"), expirations: [
      { expiry: exp_near, date: Date.new(2027, 10, 15), dte: 385, fetched_at: Time.zone.parse("2026-09-25 20:53"),
        calls: [ quote(100, bid: 52, ask: 54, delta: 0.81), quote(150, bid: 9, ask: 11, delta: 0.45),
                 quote(170, bid: 4, ask: 6, delta: 0.31) ] },
      { expiry: exp_far, date: Date.new(2029, 1, 19), dte: 847, fetched_at: Time.zone.parse("2026-09-25 20:53"),
        calls: [ quote(100, bid: 65, ask: 68, delta: 0.8), quote(200, bid: 20, ask: 22, delta: 0.3),
                 quote(230, bid: 14, ask: 16, delta: 0.25) ] }
    ] }
  end

  def stub_fetcher(result)
    fetcher = instance_double(LeapsCallChainFetcher, call: result)
    allow(LeapsCallChainFetcher).to receive(:new).and_return(fetcher)
    fetcher
  end

  def service_result(**params)
    stub_fetcher(chain)
    LeapsVerticalSpreadService.new(ticker: "ORCL", long_strike: "100", **params).call
  end

  before do
    allow(LeapsRankingService).to receive(:new).and_call_original
    allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
  end

  describe "GET /leaps 的外框" do
    it "1. 不帶標的和價格：沒有本區塊" do
      get "/leaps"
      expect(response.body).not_to include("leaps_vertical_spread")
    end

    it "2. 只帶標的：沒有本區塊" do
      get "/leaps", params: { symbol: "ORCL" }
      expect(response.body).not_to include("leaps_vertical_spread")
    end

    it "3. 帶標的和價格 100：有外框、指向 /leaps/vertical_spread、位置在 PMCC 之前，且不等待 sidecar" do
      LeapsPageHtml.stub_candidates!(self, "NOK")
      expect(LeapsCallChainFetcher).not_to receive(:new)

      get "/leaps", params: { symbol: "NOK", user_strike: "100" }
      frame = Nokogiri::HTML(response.body).at_css("#leaps_vertical_spread")

      expect(frame).to be_present
      expect(frame["data-behavior"]).to eq("leaps-vertical-spread")
      expect(frame["data-src"]).to eq("/leaps/vertical_spread?symbol=NOK&user_strike=100")
      expect(response.body.index('id="leaps_vertical_spread"')).to be < response.body.index("PMCC黃金法則組合")
    end

    it "3b. 沒有候選（PMCC 不顯示）時，只要有標的和價格一樣有外框" do
      get "/leaps", params: { symbol: "ORCL", user_strike: "100" }
      expect(Nokogiri::HTML(response.body).at_css("#leaps_vertical_spread")).to be_present
    end
  end

  describe "GET /leaps/vertical_spread" do
    it "4. 只帶標的和價格 100：有結果欄位、買入腳全是 100.00、數值等於 service 直接計算" do
      expected = service_result
      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100" }
      html = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("實付淨成本", "最大獲利", "損益兩平", "報價時間")
      long_labels = html.css('select[name="expiry"] option').map(&:text)
      expect(long_labels).to all(include("｜100.00｜"))
      expect(response.body).to include(expected[:result][:display][:net_cost],
                                       expected[:result][:display][:max_profit],
                                       expected[:result][:display][:breakeven])
      expect(response.body).not_to include("<html")
    end

    it "4b. 帶完整參數（expiry、short_strike）：數值等於 service 直接計算" do
      expected = service_result(expiry: exp_near, short_strike: "150")
      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100", expiry: exp_near, short_strike: "150" }

      expect(response.body).to include(expected[:result][:display][:net_cost],
                                       expected[:result][:display][:risk_reward])
      expect(Nokogiri::HTML(response.body).at_css('select[name="short_strike"] option[selected]').text)
        .to start_with("150.00")
    end

    it "4c. 口數 2（S3 第 8 點）：route → controller → service，卡片金額加倍，與 service 直接計算一致" do
      expected = service_result(expiry: exp_near, short_strike: "150", contracts: "2")
      get "/leaps/vertical_spread",
          params: { symbol: "ORCL", user_strike: "100", expiry: exp_near, short_strike: "150", contracts: "2" }

      html = Nokogiri::HTML(response.body)
      net_cost = html.at_css("[data-vs-tour-anchor='net_cost'] [data-vs-value]").text
      # 預設 100（mid 53）、150（mid 10）→ 淨成本 43 × 100 × 2
      expect(net_cost).to eq("$8,600.00")
      expect(net_cost).to eq(expected[:result][:cards][:net_cost][:mid])
      expect(html.at_css("input[name='contracts']")["value"]).to eq("2")
      expect(JSON.parse(html.at_css("[data-vs-payoff]")["data-vs-payoff-params"])).to include("contracts" => "2")
    end

    it "4d. 口數不是正整數：顯示錯誤，不顯示計算數字" do
      stub_fetcher(chain)
      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100", contracts: "-1" }

      expect(response.body).to include("口數須為正整數：-1")
      expect(response.body).not_to include("實付淨成本")
    end

    it "5. 缺少 ticker 或價格：422" do
      get "/leaps/vertical_spread", params: { symbol: "ORCL" }
      expect(response).to have_http_status(:unprocessable_entity)
      get "/leaps/vertical_spread", params: { user_strike: "100" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "6. 無效組合：200，顯示紅字說明" do
      stub_fetcher(chain)
      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100", expiry: exp_near, short_strike: "100" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("賣出腳履約價 100.00 必須高於買入腳履約價 100.00")
      expect(response.body).not_to include("實付淨成本")
    end

    it "7. fetcher 停滯：顯示「Barchart 讀取失敗」與「重試」，不顯示計算數字" do
      stub_fetcher({ status: :error, code: :stalled, message: "讀取 2028-01-21 chain 超過 30 秒沒有回應" })
      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100" }

      expect(response.body).to include("Barchart 讀取失敗：讀取 2028-01-21 chain 超過 30 秒沒有回應", "重試")
      expect(response.body).not_to include("實付淨成本")
    end

    describe "8. 功能定義 6 的錯誤" do
      {
        "查無代號" => [ { status: :error, code: :symbol_not_found, message: "查無股票代號 ZZZZQ" }, "100", "查無股票代號 ZZZZQ" ],
        "沒有 LEAPS" => [ { status: :error, code: :no_leaps, message: "BRK.A 沒有適合的 LEAPS 標的" }, "100",
                          "BRK.A 沒有適合的 LEAPS 標的" ]
      }.each do |name, (fetch_result, strike, message)|
        it name do
          stub_fetcher(fetch_result)
          get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: strike }
          expect(response.body).to include(message)
          expect(response.body).not_to include("實付淨成本")
        end
      end

      it "查無履約價" do
        stub_fetcher(chain)
        get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "101.37" }
        expect(response.body).to include("ORCL 的 LEAPS 中查無履約價 101.37；最接近的履約價：100.00、150.00")
        expect(response.body).not_to include("實付淨成本")
      end

      it "履約價沒有有效報價" do
        no_quote = chain.deep_dup
        no_quote[:expirations].each { |e| e[:calls][0] = quote(100, bid: 0, ask: 0, last: 0) }
        stub_fetcher(no_quote)
        get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100" }
        expect(response.body).to include("履約價 100.00 在所有 LEAPS 到期日都沒有有效報價")
        expect(response.body).not_to include("實付淨成本")
      end

      it "沒有合格的賣出腳" do
        no_short = chain.deep_dup
        no_short[:expirations].each { |e| e[:calls] = [ e[:calls].first, quote(300) ] }
        stub_fetcher(no_short)
        get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100" }
        expect(response.body).to include("沒有符合條件的價外賣出腳")
        expect(response.body).not_to include("實付淨成本")
      end
    end

    it "progress=1：回傳 fetcher 寫入的進度 JSON，不觸發抓取、不做 CDP 預檢" do
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      Rails.cache.write(LeapsCallChainFetcher.progress_key("ORCL"), { state: "running", done: 2, total: 6,
                                                                      stage: "讀取 2028-01-21 chain（3/6）" })
      expect(LeapsCallChainFetcher).not_to receive(:new)
      expect_any_instance_of(LeapsRecommendationsController).not_to receive(:cdp_online?)

      get "/leaps/vertical_spread", params: { symbol: "orcl", progress: "1" }

      expect(response.parsed_body).to include("state" => "running", "done" => 2, "total" => 6)
    ensure
      Rails.cache = ActiveSupport::Cache::NullStore.new
    end

    describe "payoff=1（P7 到期日預估股價；tasks/leaps-vertical-fix.md S3）" do
      # FX-1，費用 0
      let(:legs) do
        { payoff: "1", long_strike: "100.0", long_bid: "74.95", long_ask: "79.05", long_price: "77.0",
          short_strike: "240.0", short_bid: "29.7", short_ask: "33.7", short_price: "31.7", spot: "150.0",
          quote_date: "2026-09-30", expiry: "2028-12-15", dividend_annual: "0", contracts: "1" }
      end

      before { allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0")) }

      it "回傳平倉＋到期損益片段，不觸發抓取、不做 CDP 預檢" do
        expect(LeapsCallChainFetcher).not_to receive(:new)
        expect_any_instance_of(LeapsRecommendationsController).not_to receive(:cdp_online?)

        get "/leaps/vertical_spread", params: legs.merge(target_price: "200", close_date: "2028-12-15")

        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML.fragment(response.body).text)
          .to eq("→ 平倉理論損益 +$5,470.00（保守 +$4,660.00）｜到期損益 +$5,470.00（+120.75%）")
      end

      it "平倉日 = 報價日：平倉損益低於到期損益 5,470" do
        get "/leaps/vertical_spread", params: legs.merge(target_price: "200", close_date: "2026-09-30")

        close = Nokogiri::HTML.fragment(response.body).at_css("[data-vs-close-pnl]").text
        expect(close.delete("+$,").to_d).to be_between(0, 5470).exclusive
      end

      it "IV 調整超出範圍：422" do
        get "/leaps/vertical_spread", params: legs.merge(target_price: "200", iv_shift: "60")
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "不接受費率參數：費率一律讀設定檔" do
        allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0.05"))
        get "/leaps/vertical_spread", params: legs.merge(target_price: "300", close_date: "2028-12-15", fee_per_leg: "0")

        # 到期損益 = 9,470 − 開倉 0.10 − 平倉 0.10
        expect(Nokogiri::HTML.fragment(response.body).at_css("[data-vs-expiry-pnl]").text).to eq("+$9,469.80")
      end

      it "預估價空白：200、空片段" do
        get "/leaps/vertical_spread", params: legs.merge(target_price: "")
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("")
      end

      it "參數不合法：422、紅字訊息（逐字跳脫）" do
        get "/leaps/vertical_spread", params: legs.merge(target_price: "<b>x</b>")
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("預估股價格式錯誤：&lt;b&gt;x&lt;/b&gt;")
      end

      it "預估價 NaN：422（不可變成 500）" do
        get "/leaps/vertical_spread", params: legs.merge(target_price: "NaN")
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("預估股價格式錯誤：NaN")
      end
    end

    it "CDP 離線：直接回報，不呼叫 fetcher（全域 CDP 預檢規則）" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(false)
      expect(LeapsCallChainFetcher).not_to receive(:new)

      get "/leaps/vertical_spread", params: { symbol: "ORCL", user_strike: "100" }

      expect(response.body).to include("CDP 未連線", "wsl --shutdown")
      expect(response.body).not_to include("實付淨成本")
    end
  end

  describe "9. 既有行為回歸：除了新增外框，/leaps 的 HTML 與加入前完全相同" do
    around { |ex| travel_to(LeapsPageHtml::FROZEN_AT) { ex.run } }

    LeapsPageHtml::CASES.each do |name, spec|
      it name do
        LeapsPageHtml.stub_candidates!(self, spec[:params][:symbol]) if spec[:candidates]
        get "/leaps", params: spec[:params]

        expect(LeapsPageHtml.normalize(response.body)).to eq(LeapsPageHtml.read_baseline(name))
      end
    end
  end
end
