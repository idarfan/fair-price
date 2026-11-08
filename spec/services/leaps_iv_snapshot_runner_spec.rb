# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P4：每日 IV 快照的標的選擇、逐一執行、失敗隔離、backfill。
RSpec.describe LeapsIvSnapshotRunner do
  subject(:runner) { described_class.new(logger: Logger.new(log), config: config) }

  let(:log)    { StringIO.new }
  let(:config) do
    { "watchlist" => [ "TSM" ], "max_symbols" => 20, "per_symbol_timeout_sec" => 600, "lock_wait_sec" => 900 }
  end
  let(:services) { {} }

  def fetch_log!(symbol, status, at: 1.day.ago, type: "leaps")
    FetchLog.create!(symbol: symbol, fetch_type: type, status: status, fetched_at: at)
  end

  def stub_service(symbol, iv: { status: "success", errors: [], points: 115, cm540: 0.42794 },
                   history: { status: "success", errors: [] })
    svc = instance_double(BarchartScraperService, fetch_leaps_iv_snapshot: iv, fetch_barchart_iv_history: history)
    allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    services[symbol] = svc
  end

  before do
    allow(LeapsIvCdpLock).to receive(:exclusive) { |**_kw, &blk| blk.call }
    stub_const("LeapsIvSnapshotRunner::YIELD_GAP_S", 0)
  end

  describe "#target_symbols" do
    it "watchlist ∪ 近 30 天實際抓取過的 symbol，去重、依字母排序" do
      fetch_log!("nok", "success")
      fetch_log!("AMD", "cached")
      fetch_log!("TSM", "partial_error")
      fetch_log!("INTL", "error")                       # 只有 error 不算
      fetch_log!("ORCL", "success", at: 31.days.ago)    # 超過 30 天
      fetch_log!("CSCO", "success", type: "pmcc_short") # 不是 LEAPS 查詢

      expect(runner.target_symbols).to eq(%w[AMD NOK TSM])
    end

    it "超過 max_symbols 時只取前 N 個，其餘寫 log 略過" do
      %w[AAA BBB CCC].each { |s| fetch_log!(s, "success") }
      config["max_symbols"] = 2

      expect(runner.target_symbols).to eq(%w[AAA BBB])
      expect(log.string).to include("超過 max_symbols 2", "略過：CCC,TSM")
    end
  end

  describe "#run" do
    it "逐一取獨佔鎖執行，source 為 scheduled、逾時帶 per_symbol_timeout_sec；沒有歷史用 backfill、有就 latest" do
      fetch_log!("NOK", "success")
      BarchartIvHistory.create!(symbol: "TSM", trade_date: Date.new(2026, 11, 4), captured_at: Time.current,
                                source_url: "https://www.barchart.com/stocks/quotes/TSM/options-history")
      stub_service("NOK")
      stub_service("TSM")

      expect(runner.run).to eq("NOK" => :ok, "TSM" => :ok)
      expect(LeapsIvCdpLock).to have_received(:exclusive).twice
      expect(services["NOK"]).to have_received(:fetch_leaps_iv_snapshot).with(source: "scheduled", timeout: 600)
      expect(services["NOK"]).to have_received(:fetch_barchart_iv_history).with(mode: "backfill", source: "scheduled")
      expect(services["TSM"]).to have_received(:fetch_barchart_iv_history).with(mode: "latest", source: "scheduled")
    end

    it "單一標的失敗或拋例外不中斷其他標的，錯誤寫 log" do
      %w[AMD NOK].each { |s| fetch_log!(s, "success") }
      stub_service("AMD", iv: { status: "scraper_timeout", errors: [ "爬蟲超過 600 秒沒有結束" ] })
      allow(BarchartScraperService).to receive(:new).with("NOK").and_raise(RuntimeError, "CDP 斷線")
      stub_service("TSM")

      expect(runner.run).to eq("AMD" => :error, "NOK" => :error, "TSM" => :ok)
      expect(log.string).to include("爬蟲超過 600 秒沒有結束", "NOK 失敗：RuntimeError: CDP 斷線")
    end

    it "log 行在有沒載入的到期日時附 missing=，沒有時格式不變（P7.1）" do
      fetch_log!("AMD", "success")
      stub_service("AMD", iv: { status: "success", errors: [], points: 604, cm540: 0.57268, missing: [ "2029-01-19" ] })
      stub_service("TSM", iv: { status: "success", errors: [], points: 294, cm540: 0.42085, missing: [] })

      expect(runner.run).to eq("AMD" => :ok, "TSM" => :ok)
      amd, tsm = log.string.lines.grep(/\[snapshot\] (AMD|TSM)：/)
      expect(amd).to include("AMD：IV success（points=604 cm540=0.57268 missing=2029-01-19）")
      expect(tsm).to include("TSM：IV success（points=294 cm540=0.42085）")
    end

    it "美股盤中依規則略過的標的記 :skipped，不算失敗" do
      skipped = { status: "skipped_regular_session", errors: [] }
      stub_service("TSM", iv: skipped, history: skipped)

      expect(runner.run).to eq("TSM" => :skipped)
    end

    it "拿不到鎖（互動查詢一直占用）只記這個標的失敗，繼續下一個" do
      fetch_log!("AMD", "success")
      calls = 0
      allow(LeapsIvCdpLock).to receive(:exclusive) do |**_kw, &blk|
        calls += 1
        raise LeapsIvCdpLock::Timeout, "等待 LEAPS 抓取鎖超過 900 秒" if calls == 1

        blk.call
      end
      stub_service("TSM")

      expect(runner.run).to eq("AMD" => :error, "TSM" => :ok)
    end
  end

  # 用真實 advisory lock：排程跑第一個標的時有互動查詢在等，第二個標的開始前查詢要先拿到鎖。
  describe "#run 與等鎖的互動查詢（真實鎖）" do
    before do
      allow(LeapsIvCdpLock).to receive(:exclusive).and_call_original
      stub_const("LeapsIvCdpLock::POLL_S", 0.05)
      stub_const("LeapsIvSnapshotRunner::YIELD_GAP_S", 0.3) # > POLL_S
      fetch_log!("AMD", "success")
    end

    let(:events) { Concurrent::Array.new }

    def run_with_waiting_query
      query = nil
      amd = instance_double(BarchartScraperService, fetch_barchart_iv_history: { status: "success", errors: [] })
      allow(amd).to receive(:fetch_leaps_iv_snapshot) do
        query = Thread.new { LeapsIvCdpLock.shared(wait: 5, label: "LEAPS 查詢", logger: Logger.new(nil)) { events << :query } }
        sleep 0.2 # 確定查詢已在等鎖
        events << :amd
        { status: "success", errors: [] }
      end
      tsm = instance_double(BarchartScraperService, fetch_barchart_iv_history: { status: "success", errors: [] })
      allow(tsm).to receive(:fetch_leaps_iv_snapshot) { events << :tsm; { status: "success", errors: [] } }
      allow(BarchartScraperService).to receive(:new).with("AMD").and_return(amd)
      allow(BarchartScraperService).to receive(:new).with("TSM").and_return(tsm)

      runner.run
      query.join
    end

    # 沒有空檔時搶不搶得到全憑時序（實測多半搶不到：2026-11-06 AMD 等到整輪跑完），不寫成測試以免不穩定。
    it "等鎖的查詢插在兩個標的之間（不必等整輪跑完）" do
      run_with_waiting_query
      expect(events).to eq(%i[amd query tsm])
    end
  end

  # P7.1：pm2 cron 提早觸發時整輪略過；cron 是 pm2 傳進來的環境變數 cron_restart。
  describe "#early_fire?" do
    let(:early) { Time.utc(2026, 11, 7, 5, 15, 56) }

    it "提早觸發：回 true，log 寫略過與下一次排定時間" do
      expect(runner.early_fire?("0 6 * * 2-6", now: early)).to be(true)
      expect(log.string).to include("提早觸發，略過", "2026-11-07T05:15:56Z", "下一次排定 2026-11-07T06:00:00Z")
    end

    it "正點：回 false，不寫 log" do
      expect(runner.early_fire?("0 6 * * 2-6", now: Time.utc(2026, 11, 7, 6))).to be(false)
      expect(log.string).to be_empty
    end

    it "沒有 cron_restart（手動執行）：回 false" do
      expect(runner.early_fire?(nil, now: early)).to be(false)
      expect(runner.early_fire?("", now: early)).to be(false)
    end

    it "不支援的 cron 字串：照跑並寫 warn" do
      expect(runner.early_fire?("*/30 6 * * *", now: early)).to be(false)
      expect(log.string).to include("無法判斷提早觸發，照常執行")
    end
  end

  describe "#backfill" do
    it "只回補 Barchart 歷史（2Y），同樣取獨佔鎖" do
      stub_service("NOK")

      expect(runner.backfill("nok")).to eq(:ok)
      expect(services["NOK"]).to have_received(:fetch_barchart_iv_history).with(mode: "backfill", source: "scheduled")
      expect(services["NOK"]).not_to have_received(:fetch_leaps_iv_snapshot)
      expect(LeapsIvCdpLock).to have_received(:exclusive).once
    end
  end
end
