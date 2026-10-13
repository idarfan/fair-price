# frozen_string_literal: true

require "rails_helper"

# leaps-deep-itm-fix.md P5：走完 F7 的非同步全流程
#   POST /leaps/analyze → 執行 job → GET /leaps/status → GET /leaps?…&job_status=success
# 只在 sidecar 邊界（Open3.capture3 啟動 Python 子程序那一刻）換成 fixture JSON；
# BarchartScraperService 的 JSON 解析／persist、ScrapeLeapsJob、排名、PMCC、controller
# 與 component 全部走真的程式。CDP 預檢用 WebMock 固定 9222 回 200，預檢邏輯照常執行。
RSpec.describe "LEAPS 非同步全流程", type: :request do
  include ActiveJob::TestHelper

  let(:symbol) { "INTC" }
  let(:spot) { 106.76 }
  let(:near_exp) { Date.current + 434 }
  let(:far_exp) { Date.current + 798 }
  let(:short_exp) { Date.current + 30 }
  # 規格 P5：「Barchart 抓取在 sidecar 邊界用 fixture 替換」。每次查詢 Stage 2 實際會送出的
  # 履約價由各 example 指定（auto＝0.60–0.90 區間加緩衝；user_strike＝中心加緩衝）。
  let(:stage2_strikes) { [] }

  # LEAPS 鏈：每 5 一檔，Δ 依價內程度遞減，$80 ≈ 0.80（與 P1 T1 同一組數字）
  let(:deltas) do
    { 70.0 => 0.96, 75.0 => 0.88, 80.0 => 0.80, 85.0 => 0.76, 90.0 => 0.72, 95.0 => 0.69,
      100.0 => 0.66, 105.0 => 0.62, 110.0 => 0.58, 115.0 => 0.54, 120.0 => 0.50, 125.0 => 0.46, 130.0 => 0.42 }
  end


  def leaps_row(strike, expiration)
    intrinsic = [ spot - strike, 0 ].max
    mid = intrinsic + 10 + (strike - 70) * 0.2
    { "expiration_date" => expiration.iso8601, "dte" => (expiration - Date.current).to_i,
      "strike" => strike, "option_type" => "Call", "bid" => (mid - 0.5).round(2), "ask" => (mid + 0.5).round(2),
      "last_price" => mid.round(2), "underlying_price" => spot, "volume" => 50, "open_interest" => 1000 + strike.to_i,
      "delta" => deltas.fetch(strike), "iv" => 0.6, "itm_probability" => 0.7, "vol_oi_ratio" => 0.05, "vega" => 0.4 }
  end

  def leaps_payload
    { "status" => "success", "underlying_price" => spot, "skipped_strikes" => [],
      "rows" => stage2_strikes.flat_map { |k| [ leaps_row(k, near_exp), leaps_row(k, far_exp) ] },
      "chain_snapshot" => { "strikes" => deltas.keys, "spot_price" => spot, "expiration" => near_exp.iso8601 } }
  end

  def pmcc_short_payload
    rows = [ [ 110.0, 0.40, 3.0 ], [ 115.0, 0.33, 2.0 ], [ 120.0, 0.27, 1.3 ], [ 125.0, 0.21, 0.8 ] ].map do |k, d, m|
      { "expiration_date" => short_exp.iso8601, "dte" => 30, "strike" => k, "option_type" => "Call",
        "bid" => m - 0.05, "ask" => m + 0.05, "mid" => m, "underlying_price" => spot, "delta" => d,
        "open_interest" => 500, "volume" => 20, "iv" => 0.55 }
    end
    { "status" => "success", "rows" => rows }
  end

  def fake_sidecar(cmd)
    payload = case File.basename(cmd[1].to_s)
    when "leaps_scraper.py"            then leaps_payload
    when "pmcc_short_call_scraper.py"  then pmcc_short_payload
    else { "status" => "error", "error" => "fixture: #{File.basename(cmd[1].to_s)} 不在本測試範圍" }
    end
    [ payload.to_json, "", instance_double(Process::Status, success?: true) ]
  end

  around do |example|
    # job 狀態（leaps_job_<id>）與 inflight 登記都存在 Rails.cache；test 環境是 :null_store，
    # 寫了等於沒寫，/leaps/status 只會回 not_found。這個 spec 換成真的記憶體快取。
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  before do
    stub_request(:get, "http://127.0.0.1:9222/json/version").to_return(status: 200, body: "{}")
    allow(Open3).to receive(:capture3) { |*cmd, **| fake_sidecar(cmd) }
  end

  def run_full_flow(params)
    post "/leaps/analyze", params: { symbol: symbol, **params }, as: :json
    job_id = JSON.parse(response.body).fetch("job_id")
    expect(job_id).to be_present

    perform_enqueued_jobs

    get "/leaps/status", params: { job_id: job_id }
    expect(JSON.parse(response.body)["status"]).to eq("success")

    get "/leaps", params: { symbol: symbol, job_status: "success", **params }
    expect(response).to have_http_status(:ok)
    WithoutReleaseNotes.doc(response.body)
  end

  def ranking_strikes(doc)
    doc.css("#leaps-ranking-table tbody tr").map { |tr| tr.css("td")[3]&.text.to_s[/\d+\.\d+/] }.compact.uniq
  end

  # PMCC 組合表：thead 有「Long Δ」那幾張表，第 4 欄（index 3）
  def pmcc_long_deltas(doc)
    doc.css("table").select { |t| t.css("thead th").map(&:text).any? { |h| h.include?("Long Δ") } }
       .flat_map { |t| t.css("tbody tr").map { |tr| tr.css("td")[3]&.text.to_s[/\d+\.\d+/] } }
       .compact.map(&:to_f)
  end

  context "預設查詢（不填履約價）" do
    # P2：LEAPS 鏈 0.60–0.90 是 75–105，加上下緩衝 70、110
    let(:stage2_strikes) { [ 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0 ] }

    it "四步都成功；候選表含 80.00；PMCC 每個 Long Δ ≥ 0.80" do
      doc = run_full_flow({})

      expect(ranking_strikes(doc)).to include("80.00")
      deltas = pmcc_long_deltas(doc)
      expect(deltas).not_to be_empty
      expect(deltas).to all(be >= PmccRankingService::LEAPS_DELTA_OK_MIN)
    end
  end

  context "user_strike=80" do
    let(:stage2_strikes) { [ 75.0, 80.0, 85.0 ] }

    it "四步都成功；不出現 Delta 不足警告；候選表含 80.00；PMCC 每個 Long Δ ≥ 0.80" do
      doc = run_full_flow(user_strike: "80")

      expect(doc.text).not_to include("含緩衝檔）在所有到期日都沒有符合")
      expect(ranking_strikes(doc)).to include("80.00")
      deltas = pmcc_long_deltas(doc)
      expect(deltas).not_to be_empty
      expect(deltas).to all(be >= PmccRankingService::LEAPS_DELTA_OK_MIN)
    end
  end

  # P3 r1 質詢 2：T2c 不 stub 排名——放進 Δ < 0.60 的真實列，讓排名篩選自己把它們擋掉
  context "user_strike=125（有掛牌、但所有到期日 Δ < 0.60）" do
    let(:stage2_strikes) { [ 120.0, 125.0, 130.0 ] }

    it "四步都成功；排名篩選後為空，維持 Delta 不足警告，不顯示「已不是最新」" do
      doc = run_full_flow(user_strike: "125")

      expect(doc.text).to include("這個履約價 125（含緩衝檔）在所有到期日都沒有符合 Delta ≥ 0.60")
      expect(doc.text).not_to include("已不是最新")
      expect(LeapsOptionChainSnapshot.where(symbol: symbol, strike: 125.0)).to exist
    end
  end
end
