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
