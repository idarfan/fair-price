# frozen_string_literal: true

require "rails_helper"

# 三個價格情境 widget 的輪詢端點。
# 重點在「不同的失敗原因要給不同的處置訊息」——全部回一句「抓取失敗」
# 會讓使用者不知道該去登入、還是該去圖上掛指標、還是該修 CDP。
# type: :request 要明寫——這個專案沒有開 infer_spec_type_from_file_location!，
# 放在 spec/requests/ 底下不會自動帶上，登入也就不會自動發生
# （spec/support/auth_helpers.rb 的 auto-auth 掛在 type: :request 上）。
RSpec.describe "GET /leaps/price_context", type: :request do
  let(:symbol) { "TSTX" }

  # test 環境的 cache_store 是 :null_store（config/environments/test.rb），
  # 寫進去讀不回來。這個端點的「排程去重鎖」與「讀 job 回報的失敗原因」
  # 兩件事都靠快取，用 null_store 測等於什麼都沒測到——換成真的 memory store。
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def create_volap
    VolapSnapshot.create!(
      symbol: symbol, scraped_at: Time.current,
      period_key: VolapSnapshot::TARGET_PERIOD_KEY,
      aggregation: VolapSnapshot::TARGET_AGGREGATION,
      price_min: 94, price_max: 182.19, zone: 22.0475, poc_index: 1,
      inputs: { "LevelSize" => 4, "Volume" => "Up/Down" },
      bars: [ { "up" => 10, "down" => 5, "is_value" => false },
              { "up" => 90, "down" => 30, "is_value" => true },
              { "up" => 40, "down" => 20, "is_value" => true },
              { "up" => 5,  "down" => 5,  "is_value" => false } ]
    )
  end

  def create_bar
    DailyBar.create!(symbol: symbol, bar_date: Date.new(2026, 9, 10),
                     open_price: 124, high_price: 129, low_price: 124,
                     close_price: 126.6, volume: 1_000)
  end

  after { Rails.cache.clear }

  it "缺 symbol 時回 422 而不是 500" do
    get "/leaps/price_context"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["status"]).to eq("error")
  end

  context "已經有快照" do
    before do
      create_volap
      create_bar
    end

    it "回傳渲染好的 HTML 片段（不是原始數字）" do
      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["html"]).to include("data-pc-key=\"poi\"")
      expect(body["html"]).to include("52WK RANGE")
      expect(body["html"]).to include("DAY&#39;S RANGE")
    end

    it "不會因為輪詢而排 job" do
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }
    end
  end

  # 2026-09-29 SHOP：VOLAP 停在 9/11、日線停在 9/10 仍一直回 ok，永遠不重抓。
  # 超過 VolapSnapshot::FRESH_WINDOW（1 小時）要重抓，抓的期間先顯示舊資料。
  context "有快照但已超過 1 小時" do
    before do
      create_volap.update!(scraped_at: 2.hours.ago)
      create_bar
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
    end

    it "排 job 重抓，回 queued（剛排、還沒開始跑） 並附上舊資料的 HTML" do
      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("queued")
      expect(body["html"]).to include("data-pc-key=\"poi\"")
    end

    # 重抓結束但 VOLAP 沒更新（例如 Barchart 圖表 chart_not_ready）：job 回報 partial。
    # 不能再回 pending 讓前端輪詢到逾時——停止、保留舊卡片並說明。
    it "job 已結束但 VOLAP 沒更新（partial）：回 partial、附舊資料與說明，不再排 job" do
      Rails.cache.write(ScrapePriceContextJob.cache_key(symbol), { status: "partial" })
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("partial")
      expect(body["message"]).to include("POI／52 週資料這次沒有更新成功")
      expect(body["html"]).to include("data-pc-key=\"poi\"")
    end
  end

  # 2026-09-21 NOK：原本的 gate 是三塊 any?，日線一有值就回 ok、job 永遠排不出去，
  # POI 與 52 週停在「載入中…」直到天荒地老。舊測試只有「三塊全有」與「三塊全無」
  # 兩種情境，正好漏掉實務上最常見的這一種。
  context "只有日線、沒有 VOLAP（兩條供給線獨立）" do
    before { create_bar }

    # 從沒抓到過 VOLAP 的標的：畫面上 POI／52 週是「暫無資料」，不能說「先顯示較早抓到的資料」。
    it "job 已結束但 VOLAP 沒抓到（partial）：回 partial，說明暫時抓不到、會自動重試" do
      Rails.cache.write(ScrapePriceContextJob.cache_key(symbol), { status: "partial" })
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("partial")
      expect(body["message"]).to include("POI／52 週資料暫時抓不到，約 1 小時後會自動重試")
      expect(body["message"]).not_to include("較早抓到的資料")
    end

    it "照樣排 job 去抓 VOLAP，不會因為日線有值就當成已經有資料" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("queued")
    end

    it "pending 時夾帶已經有的當日區間，不讓使用者對著三張空卡等" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      allow(ScrapePriceContextJob).to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      html = JSON.parse(response.body)["html"]
      expect(html).to include("DAY&#39;S RANGE")
      # 有資料的 POI 卡 key 是小寫 "poi"，空卡走 render_empty_card 用標題當 key（"POI"）。
      expect(html).not_to include('data-pc-key="poi"')
      # 還在抓，空卡這時候寫「載入中」才是對的。
      expect(html).to include("載入中")
    end

    it "抓取走到終局時回 partial：保留日線卡片，空卡不再寫「載入中」" do
      Rails.cache.write(ScrapePriceContextJob.cache_key(symbol), { status: "no_volap_plot" })

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("partial")
      expect(body["message"]).to include("Volume Profile")
      expect(body["html"]).to include("DAY&#39;S RANGE")
      expect(body["html"]).to include("暫無資料")
      expect(body["html"]).not_to include("載入中")
    end

    it "CDP 離線時也回 partial，不用一句錯誤把日線卡片洗掉" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(false)
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("partial")
      expect(body["message"]).to include("wsl --shutdown")
      expect(body["html"]).to include("DAY&#39;S RANGE")
    end
  end

  context "還沒有資料" do
    it "CDP 連得上時排一次 job 並回 queued" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("queued")
    end

    it "連續輪詢只排一次 job（cache lock）" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      expect(ScrapePriceContextJob).to receive(:perform_later).once

      3.times { get "/leaps/price_context", params: { symbol: symbol } }
    end

    it "CDP 離線時直接回報、不排 job" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(false)
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("error")
      expect(body["message"]).to include("wsl --shutdown")
    end
  end

  context "job 已回報失敗" do
    it "session 過期時叫使用者去登入 Barchart" do
      Rails.cache.write(ScrapePriceContextJob.cache_key(symbol),
                        { status: "barchart_session_expired" })

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["message"]).to include("登入 Barchart")
    end

    it "圖上沒掛 VOLAP 時叫使用者去掛指標，而不是講「抓取失敗」" do
      Rails.cache.write(ScrapePriceContextJob.cache_key(symbol), { status: "no_volap_plot" })

      get "/leaps/price_context", params: { symbol: symbol }

      message = JSON.parse(response.body)["message"]
      expect(message).to include("Volume Profile")
      expect(message).to include("模板")
    end
  end

  # 2026-10-01 RKLB：抓取失敗的結果跟成功共用 1 小時快取，使用者重新按「查詢」
  # 也只會一直看到同一句「抓取失敗」，不會重抓。失敗結果沒有任何保留的理由——
  # 它只是用來讓這一輪輪詢停下來。新的查詢（載入 /leaps?symbol=）就要清掉重抓。
  describe "GET /leaps?symbol= 重置上一輪沒成功的抓取" do
    let(:job_key) { ScrapePriceContextJob.cache_key(symbol) }

    %w[error partial barchart_session_expired no_volap_plot].each do |status|
      it "上一輪是 #{status}：清掉結果" do
        Rails.cache.write(job_key, { status: status })

        get "/leaps", params: { symbol: symbol }

        expect(Rails.cache.read(job_key)).to be_nil
      end
    end

    # 鎖由 job 結束時自己解，還在就代表真的有 job 在跑；刪掉會重複排程。
    it "上一輪失敗、但新一輪 job 正在跑：清結果、不動鎖" do
      Rails.cache.write(job_key, { status: "error" })
      ScrapePriceContextJob.acquire_lock(symbol)

      get "/leaps", params: { symbol: symbol }

      expect(Rails.cache.read(job_key)).to be_nil
      expect(ScrapePriceContextJob.running?(symbol)).to be(true)
    end

    it "上一輪成功：結果保留，不重抓" do
      Rails.cache.write(job_key, { status: "success" })

      get "/leaps", params: { symbol: symbol }

      expect(Rails.cache.read(job_key)).to eq({ status: "success" })
    end

    it "工作還在跑（沒有結果、只有鎖）：不動鎖，避免重複排程" do
      ScrapePriceContextJob.acquire_lock(symbol)

      get "/leaps", params: { symbol: symbol }

      expect(ScrapePriceContextJob.running?(symbol)).to be(true)
    end

    it "清掉之後，下一次輪詢會重新排 job 而不是回舊的失敗訊息" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      Rails.cache.write(job_key, { status: "error" })

      get "/leaps", params: { symbol: symbol }

      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once
      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("queued")
    end

    it "輪詢端點本身不清失敗結果（否則會變成無限重抓）" do
      Rails.cache.write(job_key, { status: "error" })

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("error")
      expect(Rails.cache.read(job_key)).to eq({ status: "error" })
    end
  end

  it "LEAPS 頁把前端輪詢上限（毫秒）帶在輪詢根節點上，跟後端 job 最長時間同一個來源" do
    get "/leaps", params: { symbol: symbol }

    expected = ScrapePriceContextJob.poll_budget_s * 1000
    expect(response.body).to match(/id="leaps-price-context"[^>]*data-poll-timeout-ms="#{expected}"/)
  end

  # 2026-10-01 RKLB：job 先抓 VOLAP 再抓日線。VOLAP 一寫進 DB 就通過 fresh gate
  # 回 ok，前端停止輪詢，日線約 14 秒後才寫進來，當日區間永遠停在「載入中…」。
  describe "VOLAP 已新鮮時的 ok 判定" do
    let(:job_key) { ScrapePriceContextJob.cache_key(symbol) }

    before { create_volap }

    it "抓取還在跑（有鎖、沒有結果、執行中）：回 pending 並附上已有的卡片，不重複排程" do
      ScrapePriceContextJob.acquire_lock(symbol)
      ScrapePriceContextJob.record_phase(symbol, :running)
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("pending")
      expect(body["html"]).to include("data-pc-key=\"poi\"")
    end

    it "鎖是 server 重啟前的程序留下的：不當成還在跑，回 ok" do
      create_bar
      Rails.cache.write(ScrapePriceContextJob.lock_key(symbol), "dead-process-owner")

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("ok")
    end

    it "抓取跑完（job 已解鎖、有結果）：回 ok，三張卡都有" do
      create_bar
      Rails.cache.write(job_key, { status: "success" })

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["html"]).to include("DAY&#39;S RANGE")
    end

    it "回 ok 但日線缺：空卡顯示「暫無資料」，不是永遠的「載入中…」" do
      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["html"]).to include("暫無資料")
      expect(body["html"]).not_to include("載入中")
    end
  end

  # 並行化 S4：S2 之後抓取可能排在別人的 LEAPS（3–5 分鐘）後面。
  # 進行中要分成 queued（排隊，不算進前端的逾時）與 pending（爬蟲真的在跑）。
  describe "進行中的兩種狀態" do
    before { ScrapePriceContextJob.acquire_lock(symbol) }

    # 進行中不排新 job，所以不做 CDP 預檢；CDP 暫時離線也不能把正在跑的抓取說成失敗。
    it "進行中時不做 CDP 預檢" do
      ScrapePriceContextJob.record_phase(symbol, :running)
      expect_any_instance_of(LeapsRecommendationsController).not_to receive(:cdp_online?)

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("pending")
    end

    it "已排程但 job 還沒開始（沒有階段紀錄）：queued" do
      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("queued")
    end

    it "爬蟲在等抓取名額：queued" do
      ScrapePriceContextJob.record_phase(symbol, :queued)

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("queued")
    end

    it "爬蟲拿到名額、正在跑：pending" do
      ScrapePriceContextJob.record_phase(symbol, :running)

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("pending")
    end

    it "VOLAP 已新鮮、但日線那支還在排隊：queued，附上已有的卡片" do
      create_volap
      ScrapePriceContextJob.record_phase(symbol, :queued)

      get "/leaps/price_context", params: { symbol: symbol }

      body = JSON.parse(response.body)
      expect(body["status"]).to eq("queued")
      expect(body["html"]).to include("data-pc-key=\"poi\"")
    end

    it "排隊中不會重複排程" do
      expect(ScrapePriceContextJob).not_to receive(:perform_later)

      get "/leaps/price_context", params: { symbol: symbol }
    end
  end
end
