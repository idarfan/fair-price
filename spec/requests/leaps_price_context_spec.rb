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

  # 2026-09-21 NOK：原本的 gate 是三塊 any?，日線一有值就回 ok、job 永遠排不出去，
  # POI 與 52 週停在「載入中…」直到天荒地老。舊測試只有「三塊全有」與「三塊全無」
  # 兩種情境，正好漏掉實務上最常見的這一種。
  context "只有日線、沒有 VOLAP（兩條供給線獨立）" do
    before { create_bar }

    it "照樣排 job 去抓 VOLAP，不會因為日線有值就當成已經有資料" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("pending")
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
    it "CDP 連得上時排一次 job 並回 pending" do
      allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
      expect(ScrapePriceContextJob).to receive(:perform_later).with(symbol).once

      get "/leaps/price_context", params: { symbol: symbol }

      expect(JSON.parse(response.body)["status"]).to eq("pending")
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
end
