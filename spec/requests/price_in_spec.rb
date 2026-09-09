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

  # 2026-09-09 新增：判斷貴賤唯一不需要使用者填任何假設的數字。
  #
  # 案例用 NOK 的真實數字：現價 $10.93、TTM EPS $0.1267、FY2027 預測 $0.44–$0.60。
  # 本益比 (P/E) 那一列會算出 86 倍，看起來像「市場願意給 86 倍」，
  # 換成預測 EPS 當分母就變成 18.2–24.8 倍——後者才是市場真正的定價基準。
  describe "隱含倍數（現價 ÷ 分析師預測 EPS）" do
    around do |example|
      original    = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    def stub_nok(estimates)
      stub_request(:get, "https://finnhub.io/api/v1/quote")
        .with(query: hash_including(symbol: "NOK"))
        .to_return(status: 200, body: { c: 10.93, l: 10.80, h: 11.02, t: 1_757_251_800 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://finnhub.io/api/v1/stock/metric")
        .with(query: hash_including(symbol: "NOK"))
        .to_return(status: 200, body: { metric: { "epsTTM" => 0.1267 } }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://finnhub.io/api/v1/stock/peers")
        .with(query: hash_including(symbol: "NOK")).to_return(status: 200, body: "[]")
      allow_any_instance_of(YahooFinanceService).to receive(:eps_estimates).and_return(estimates)
    end

    let(:both_years) do
      {
        current_year: { low: 0.38, high: 0.45, avg: 0.41, analysts: 9,  end_date: "2026-12-31" },
        next_year:    { low: 0.44, high: 0.60, avg: 0.50, analysts: 11, end_date: "2027-12-31" }
      }
    end

    def render_after_quote
      get "/price_in/quote", params: { ticker: "NOK" }
      get "/price_in", params: { ticker: "NOK", price: 10.93,
                                 price_as_of: "2026-09-09T10:00:00+08:00" }
    end

    # 高 EPS 對應低倍數：區間低端必須用 est.high 去除。寫反會得到一個上下顛倒
    # 但兩端都「看起來合理」的區間，沒有人會發現。
    it "取下一財政年度，且區間低端由預測高標算出" do
      stub_nok(both_years)
      render_after_quote

      expect(response.body).to include("隱含倍數（分析師預測 FY2027）")
      expect(response.body).to include("18.2 - 24.8 倍")   # 10.93/0.60, 10.93/0.44
    end

    it "下一財政年度缺漏時退回本財政年度，年度標籤跟著換" do
      stub_nok(both_years.merge(next_year: nil))
      render_after_quote

      expect(response.body).to include("隱含倍數（分析師預測 FY2026）")
      expect(response.body).to include("24.3 - 28.8 倍")   # 10.93/0.45, 10.93/0.38
    end

    it "完全沒有分析師預測時顯示破折號，不顯示年度" do
      stub_nok(nil)
      render_after_quote

      expect(response.body).to include("隱含倍數（分析師預測）")
      expect(response.body).to include(
        %(id="price-in-implied-forward-pe" class="text-[20px] font-bold text-gray-900">—<)
      )
    end

    # 這一列刻意不給「帶入」：把它填進圖 A 的倍數，反推出來的所需 EPS
    # 必然等於分析師預測本身，又是一次循環論證。
    it "不提供「帶入」按鈕" do
      stub_nok(both_years)
      render_after_quote

      expect(response.body).not_to include("price-in-apply-implied-forward")
    end
  end

  # 教學的數字必須跟著使用者的輸入走。寫死範例等於在一個「拿你自己的數字
  # 演一次」的工具裡放別人的作業，而 price in 的誤判恰恰都發生在
  # 「套到自己身上」那一步。
  describe "教學說明（頁面最底）" do
    it "預設收摺，靜態章節永遠顯示" do
      get "/price_in"

      expect(response.body).to include("Price-In 工具教學：這張圖真正在說什麼")
      expect(response.body).to include("圓點在色帶左側不等於便宜")
      expect(response.body).to include("工具刻意不告訴你「合理倍數」")
    end

    # 參數錯誤時不出圖，但教學說明照樣要在——那正是使用者最需要它的時候。
    it "參數錯誤而不出圖時仍然顯示" do
      get "/price_in", params: { price: -1 }

      expect(response.body).to include("這些欄位需要修正")
      expect(response.body).to include("Price-In 工具教學：這張圖真正在說什麼")
    end

    # 只掃教學那一塊：匯出浮水印的 price_in.export.brand 本來就帶著 %{ticker}，
    # 由前端在匯出時代入，整頁掃會被它誤判。
    def tutorial_html = response.body[/📘.*?<\/details>/m]

    it "資料不齊時顯示提示，不顯示半套數字" do
      get "/price_in"

      expect(tutorial_html).to include("按「帶入現價」之後，這一節會用")
      expect(tutorial_html).not_to include("%{")   # 代入漏了會原樣留在畫面上
    end

    it "資料齊備時教學裡沒有未代入的佔位符" do
      get "/price_in", params: { ticker: "TEST", price: 100, eps_ttm_hint: 2.0,
                                 eps_band_low: 4, eps_band_high: 6, eps: 5,
                                 chart_b_multiples: "10,20,30", entry_b_price: 80 }

      expect(tutorial_html).not_to include("%{")
    end

    context "依使用者輸入推算" do
      # 現價 100、TTM EPS 2 → 50 倍；預測 4-6（中點 5）→ 隱含 16.7-25 倍；
      # 圖 B 未來 EPS 5、倍數 10/20/30、假設買入價 80。全部可手算驗證。
      let(:params) do
        { ticker: "TEST", price: 100, eps_ttm_hint: 2.0,
          eps_band_low: 4, eps_band_high: 6, fiscal_year_label: "FY2031",
          eps: 5, chart_b_multiples: "10,20,30", entry_b_price: 80 }
      end

      it "第三節用使用者的股價與 TTM EPS 算循環論證" do
        get "/price_in", params: params

        expect(response.body).to include("TEST 現價 $100.00 ÷ TTM EPS $2.00 = 50.0 倍")
      end

      it "第四節用使用者的預測區間算隱含倍數（低端由預測高標算出）" do
        get "/price_in", params: params

        expect(response.body).to include("$100.00 ÷ $6.00 = 16.7 倍")
        expect(response.body).to include("$100.00 ÷ $4.00 = 25.0 倍")
        expect(response.body).to include("FY2031 預估盈利的 16.7 倍 到 25.0 倍")
      end

      # 表一：固定 EPS 5、買入基準 100，倍數 10/20/30 → 目標價 50/100/150
      it "第五節的表用使用者填的倍數，不是寫死的 15/20/25" do
        get "/price_in", params: params

        expect(response.body).to include("10 倍")
        expect(response.body).to include("$50.00")
        expect(response.body).to include("-50.0%")   # 50 / 100 - 1
        expect(response.body).to include("+50.0%")   # 150 / 100 - 1
        expect(response.body).not_to include("+266.0%")
      end

      # 表二：固定倍數取中位數 20 → 目標價 100；買入價 100 與 80
      it "第六節的表用使用者的兩個買入價" do
        get "/price_in", params: params

        expect(response.body).to include("$100.00（買入基準）")
        expect(response.body).to include("$80.00")
        expect(response.body).to include("+25.0%")   # 100 / 80 - 1
      end

      it "第五節的補充句只在有 TTM EPS 時出現" do
        get "/price_in", params: params
        expect(response.body).to include("EPS 若真的從 $2.00 成長到 $5.00（+150%）")

        get "/price_in", params: params.except(:eps_ttm_hint)
        expect(response.body).not_to include("EPS 若真的從")
      end

      it "換一檔股票、換一組數字，教學跟著換" do
        get "/price_in", params: params.merge(ticker: "OTHER", price: 60, eps_ttm_hint: 1.5)

        expect(response.body).to include("OTHER 現價 $60.00 ÷ TTM EPS $1.50 = 40.0 倍")
        expect(response.body).not_to include("TEST 現價")
      end

      it "分歧度由使用者的區間算出" do
        get "/price_in", params: params

        expect(response.body).to include("$4.00 到 $6.00 的寬度（±20%）")
      end
    end
  end
end
