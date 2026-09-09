# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Price-In 反推工具", type: :request do
  describe "GET /price_in" do
    # 案例 1：無參數就該看到圖 A。圖 B 是空狀態，不是錯誤狀態。
    it "無參數時以預設值出圖 A，圖 B 為空狀態且不含錯誤字樣" do
      get "/price_in"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$7.45")            # 223.55 / 30
      expect(response.body).to include("這裡會畫出同樣盈利在不同買入價下的報酬差距")
      expect(response.body).not_to include("這些欄位需要修正")
    end

    it "案例 2：price=300 時圖 A 跟著變（300 / 25）" do
      get "/price_in", params: { price: 300 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$12.00")
    end

    it "案例 3：帶 eps 時圖 B 出圖" do
      get "/price_in", params: { eps: 11.02 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("+62.7%")
    end

    # 案例 4：參數不合法回 200 並顯示錯誤。轉址或 500 會把使用者辛苦填的
    # query string 丟掉，而那正是他要拿來重現這張圖的東西。
    it "案例 4：price=-1 時回 200、顯示錯誤、且不出圖" do
      get "/price_in", params: { price: -1 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("這些欄位需要修正")
      expect(response.body).not_to include(PriceIn::ChartACardComponent::CANVAS_ID)
      expect(response.body).not_to include(PriceIn::ChartBCardComponent::CANVAS_ID)
    end

    it "合法參數時圖表 canvas 存在" do
      get "/price_in", params: { eps: 11.02 }

      expect(response.body).to include(PriceIn::ChartACardComponent::CANVAS_ID)
      expect(response.body).to include(PriceIn::ChartBCardComponent::CANVAS_ID)
    end

    it "情境完整走 query string，URL 可重現同一張圖" do
      params = { ticker: "AVGO", price: 300, chart_a_multiples: "20,40", fiscal_year_label: "FY2030" }
      get "/price_in", params: params

      expect(response.body).to include("AVGO")
      expect(response.body).to include("$15.00")   # 300 / 20
      expect(response.body).to include("$7.50")    # 300 / 40
      expect(response.body).to include("FY2030")
    end
  end

  # 2026-09-09 回歸：按「重新出圖」是一次整頁 GET，估值數字原本只活在 JS
  # 記憶體裡，重載就全變成破折號。改由伺服器端從快取還原。
  describe "重新出圖後保留估值對照" do
    around do |example|
      original    = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    def stub_upstream(symbol = "MRVL")
      stub_request(:get, "https://finnhub.io/api/v1/quote")
        .with(query: hash_including(symbol: symbol))
        .to_return(status: 200, body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://finnhub.io/api/v1/stock/metric")
        .with(query: hash_including(symbol: symbol))
        .to_return(status: 200, body: { metric: { "epsTTM" => 3.03, "forwardPE" => 35.87 } }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://finnhub.io/api/v1/stock/peers")
        .with(query: hash_including(symbol: symbol)).to_return(status: 200, body: "[]")
      allow_any_instance_of(YahooFinanceService).to receive(:eps_estimates).and_return(nil)
    end

    it "帶入現價後重載（帶 price_as_of）仍顯示本益比區間" do
      stub_upstream
      get "/price_in/quote", params: { ticker: "MRVL" }   # 暖快取

      get "/price_in", params: { price_as_of: "2026-09-09T10:00:00+08:00" }
      expect(response.body).to include("69.59 - 73.82x")
      expect(response.body).to include("以 TTM EPS $3.03")
    end

    it "沒按過帶入現價（無 price_as_of）時不從快取還原，也不打上游" do
      stub_upstream
      get "/price_in/quote", params: { ticker: "MRVL" }

      get "/price_in"
      expect(response.body).to include(%(id="price-in-current-pe" class="text-[20px] font-bold text-gray-900">—<))
    end

    it "帶入現價時順便暖 logo 快取，之後開圖不再打上游" do
      stub_upstream
      stub_request(:get, "https://finnhub.io/api/v1/stock/profile2")
        .with(query: hash_including(symbol: "MRVL"))
        .to_return(status: 200, body: { logo: "https://example.test/MRVL.png", name: "Marvell" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/price_in/quote", params: { ticker: "MRVL" }
      WebMock.reset_executed_requests!

      get "/price_in"
      expect(response.body).to include("https://example.test/MRVL.png")
      expect(a_request(:get, /finnhub/)).not_to have_been_made
    end

    it "沒有 logo 快取時退回 emoji，不打上游" do
      get "/price_in"

      expect(response.body).to include("📈")
      expect(a_request(:get, /finnhub/)).not_to have_been_made
    end

    # 只讀快取、不打上游——「重新出圖」不該變成一次隱形的報價請求。
    it "快取沒命中時顯示破折號，不觸發任何上游請求" do
      get "/price_in", params: { price_as_of: "2026-09-09T10:00:00+08:00", ticker: "NOPE" }

      expect(response).to have_http_status(:ok)
      expect(a_request(:get, /finnhub/)).not_to have_been_made
    end
  end

  describe "匯出（S8）" do
    it "離屏匯出卡存在，且不是用 display:none 藏起來的" do
      get "/price_in", params: { eps: 11.02 }

      expect(response.body).to include(%(id="price-in-export-chart_a"))
      expect(response.body).to include(%(id="price-in-export-chart_b"))
      expect(response.body).to include("pi-export-stage")
    end

    it "匯出卡含品牌字串與代號（換股票頁首必須跟著變）" do
      get "/price_in", params: { ticker: "AVGO" }

      expect(response.body).to include("老衲敝人在下我 / AVGO")
      expect(response.body).not_to include("老衲敝人在下我 / MRVL")
    end

    it "匯出卡含署名與 PRICE IN 標記" do
      get "/price_in"

      expect(response.body).to include("@ohmy48915286")
      expect(response.body).to include("PRICE IN")
    end

    it "頁尾在沒有報價時顯示手動輸入" do
      get "/price_in"
      expect(response.body).to include("價格為手動輸入")
    end

    it "頁尾在有報價時顯示報價基準" do
      get "/price_in", params: { price_as_of: "2026-09-07T13:45:00+08:00" }
      expect(response.body).to include("報價基準 2026-09-07 13:45")
    end

    it "PNG 與 PDF 兩個按鈕都在" do
      get "/price_in", params: { eps: 11.02 }

      expect(response.body).to include(%(id="price-in-export-chart_a-png"))
      expect(response.body).to include(%(id="price-in-export-chart_a-pdf"))
      expect(response.body).to include(%(id="price-in-export-chart_b-pdf"))
    end

    it "圖 B 空狀態時不產生匯出卡（沒有圖可匯）" do
      get "/price_in"

      expect(response.body).to include(%(id="price-in-export-chart_a"))
      expect(response.body).not_to include(%(id="price-in-export-chart_b"))
    end

    it "匯出卡帶年度（缺年度的圖會誤導）" do
      get "/price_in", params: { fiscal_year_label: "FY2031" }
      expect(response.body).to include("FY2031 需要的 EPS")
    end
  end

  describe "歸屬稽核（S8.3）" do
    it "來源欄位提到機構名但未列入白名單 → 稽核島列出命中" do
      get "/price_in", params: { eps_band_low: 6.6, eps_band_high: 7.24, eps_band_label: "美銀預估" }

      island = response.body[/<script type="application\/json" id="price-in-audit-chart_a">(.*?)<\/script>/m, 1]
      expect(island).to include("美銀")
      expect(island).to include("null")   # allowed_by 為 null＝未放行
    end

    it "白名單含該機構 → 標記為已放行" do
      get "/price_in", params: {
        eps_band_low: 6.6, eps_band_high: 7.24, eps_band_label: "美銀預估",
        attribution_sources: "美銀 2026/09 研報"
      }

      island = response.body[/<script type="application\/json" id="price-in-audit-chart_a">(.*?)<\/script>/m, 1]
      expect(island).to include("2026/09")
    end

    it "乾淨文案時稽核島為空陣列" do
      get "/price_in"

      island = response.body[/<script type="application\/json" id="price-in-audit-chart_a">(.*?)<\/script>/m, 1]
      expect(island).to eq("[]")
    end

    # locale 與元件內不得出現任何機構名——寫進文案等於在還沒填來源時
    # 就先替使用者掛上一個歸屬。
    it "locale 與元件檔案內不含機構名" do
      files = Dir[Rails.root.join("app/components/price_in/*.rb")] +
              [ Rails.root.join("config/locales/price_in.zh-TW.yml").to_s ]
      pattern = /美銀|美银|BofA|高盛|Goldman|摩根|Morgan|巴克萊|巴克莱|Barclays|UBS|花旗|Citi|Stifel|Cantor/

      offenders = files.select { |f| File.read(f).match?(pattern) }
      expect(offenders).to be_empty
    end

    it "只有繁中 locale，不建其他語系檔" do
      expect(Dir[Rails.root.join("config/locales/price_in.*")].map { |f| File.basename(f) })
        .to eq([ "price_in.zh-TW.yml" ])
    end
  end

  # 案例 5
  describe "sidebar 入口" do
    it "含新入口的 href，且該 href 可被路由解析" do
      entry = FairValue::AppSwitcherComponent::APP_LINKS.find { |a| a[:label].include?("Price-In") }

      expect(entry[:href]).to eq("/price_in")
      expect(Rails.application.routes.recognize_path(entry[:href]))
        .to eq(controller: "price_in", action: "index")
    end

    it "入口是清單最後一列" do
      expect(FairValue::AppSwitcherComponent::APP_LINKS.last[:label]).to include("Price-In")
    end
  end

  describe "GET /price_in/quote" do
    around do |example|
      original    = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    def stub_quote(symbol, body:, status: 200)
      stub_request(:get, "https://finnhub.io/api/v1/quote")
        .with(query: hash_including(symbol: symbol))
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "案例 5：合法代號回 200 JSON，含 price 與 as_of" do
      stub_quote("MRVL", body: { c: 223.55, t: 1_757_251_800 })
      get "/price_in/quote", params: { ticker: "MRVL" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ok"]).to be(true)
      expect(body["price"]).to eq(223.55)
      expect(body["as_of"]).to be_present
    end

    it "案例 6：非法代號格式回 422，body 含錯誤訊息" do
      get "/price_in/quote", params: { ticker: "TOOLONG1" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to include("格式不正確")
    end

    # 案例 7：上游失敗固定回 200 + error_code，不可 500。
    # 這是一個「可以失敗」的輔助功能，圖表照常以現有價格重繪。
    it "案例 7：上游失敗回 200 與 error_code，不是 500" do
      stub_quote("MRVL", body: {}, status: 500)
      get "/price_in/quote", params: { ticker: "MRVL" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be(false)
      expect(response.parsed_body["error_code"]).to eq("upstream_error")
    end

    it "查無代號回 not_found" do
      stub_quote("NOPE", body: { c: 0, t: 0 })
      get "/price_in/quote", params: { ticker: "NOPE" }

      expect(response.parsed_body["error_code"]).to eq("not_found")
      expect(response.parsed_body["message"]).to eq("查無此代號")
    end
  end
end
