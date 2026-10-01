# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScrapeLeapsJob, type: :job do
  let(:symbol) { "NOK" }
  let(:job_id) { "abc123def456" }

  describe "#perform — rescue path (exception from service)" do
    before do
      allow(BarchartScraperService).to receive(:new).and_raise(RuntimeError, "connection reset by peer")
    end

    it "writes error status to job cache" do
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "error", errors: [ "connection reset by peer" ] },
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      allow(Rails.cache).to receive(:write)  # allow leaps_last_errors_ write
      described_class.perform_now(symbol, job_id)
    end

    it "writes error message to leaps_last_errors_{symbol} cache" do
      allow(Rails.cache).to receive(:write)  # allow job cache write
      expect(Rails.cache).to receive(:write).with(
        "leaps_last_errors_#{symbol}",
        [ "connection reset by peer" ],
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — success path" do
    let(:fake_result) { { status: "success", errors: [] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result, fetch_pmcc_short_calls: { status: "no_candidates" })
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes success status to job cache" do
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "success", errors: [] },
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end

    it "does not write leaps_last_errors when errors is empty" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).not_to receive(:write).with("leaps_last_errors_#{symbol}", anything, anything)
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — partial_error path" do
    let(:partial_msg) { "Session 在抓取 2027-01-17 的 Options Prices 時過期，已抓到的部分可能不完整，請重新查詢" }
    let(:fake_result) { { status: "partial_error", errors: [ partial_msg ] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result, fetch_pmcc_short_calls: { status: "no_candidates" })
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes partial_error status to job cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "partial_error", errors: [ partial_msg ] },
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end

    it "writes error message to leaps_last_errors_{symbol} cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_last_errors_#{symbol}",
        [ partial_msg ],
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — session_expired path" do
    let(:fake_result) { { status: "barchart_session_expired", errors: [] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result, fetch_pmcc_short_calls: { status: "no_candidates" })
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes session_expired status to job cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "session_expired", errors: [] },
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end
  end

  # 2026-09-25 ORCL：狀態先寫 success、Short Call 後抓，前端一看到 success 就跳轉，
  # 頁面比 Short Call 早 1.5 分鐘出現，PMCC 區塊顯示「尚無 Short Call 資料，請重新查詢」。
  # 使用者決定：等 Short Call 抓完才寫狀態。
  describe "#perform — job status is written only after PMCC Short Call finishes" do
    let(:events) { [] }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: { status: "success", errors: [] })
      allow(svc).to receive(:fetch_pmcc_short_calls) { events << :pmcc; { status: "success" } }
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
      allow(Rails.cache).to receive(:write) { |key, *| events << :status if key == "leaps_job_#{job_id}" }
    end

    it "fetches PMCC Short Calls before writing the job status" do
      described_class.perform_now(symbol, job_id)
      expect(events).to eq([ :pmcc, :status ])
    end
  end

  # PMCC v3 §1/§8 鐵律：PMCC 失敗不可讓 LEAPS 查詢的 job 狀態變 error。
  describe "#perform — PMCC Short Call failure is isolated from the LEAPS result" do
    let(:fake_result) { { status: "success", errors: [] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result)
      allow(svc).to receive(:fetch_pmcc_short_calls).and_raise(RuntimeError, "PMCC Short Call 資料不完整")
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "still writes the LEAPS success status to job cache, not error" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "success", errors: [] },
        expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW
      )
      described_class.perform_now(symbol, job_id)
    end

    it "does not raise out of perform_now" do
      allow(Rails.cache).to receive(:write)
      expect { described_class.perform_now(symbol, job_id) }.not_to raise_error
    end
  end

  # 並行化 S3：同代號＋同履約價同時只跑一個 LEAPS 抓取，後來的人共用同一個 job_id。
  # 進行中的登記記下持有程序（ApplicationJob::PROCESS_TOKEN）：server 重啟砍掉
  # Async job 後，舊登記作廢，不會讓所有人卡在一個已經死掉的 job 上。
  describe ".join_or_start／進行中登記" do
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    def start(strike = nil)
      started = []
      id = described_class.join_or_start(symbol, strike) { |new_id| started << new_id }
      [ id, started ]
    end

    it "第一次查詢：產生新 job_id 並交給區塊去排程" do
      id, started = start

      expect(id).to match(/\A\h{16}\z/)
      expect(started).to eq([ id ])
    end

    it "同代號＋同履約價進行中：回同一個 job_id，不再排第二個" do
      first, = start(10.0)
      second, started = start(10.0)

      expect(second).to eq(first)
      expect(started).to be_empty
    end

    it "履約價不同就是不同的抓取（中心履約價不同，資料不能共用）" do
      a, = start(10.0)
      b, started = start(12.0)
      auto, = start(nil)

      expect([ a, b, auto ].uniq.size).to eq(3)
      expect(started).to eq([ b ])
    end

    it "代號大小寫視為同一個" do
      first = described_class.join_or_start("nok", nil) { nil }
      second = described_class.join_or_start("NOK", nil) { nil }

      expect(second).to eq(first)
    end

    it "server 重啟前的程序留下的登記作廢，重新開始" do
      Rails.cache.write(described_class.inflight_key(symbol, nil), { job_id: "deadbeefdeadbeef", owner: "dead-process" })

      id, started = start

      expect(id).not_to eq("deadbeefdeadbeef")
      expect(started).to eq([ id ])
    end

    it "排程失敗時取消登記，下一次查詢可以重新開始" do
      expect { described_class.join_or_start(symbol, nil) { raise IOError, "queue down" } }.to raise_error(IOError)

      _, started = start
      expect(started.size).to eq(1)
    end

    it "多個執行緒同時查同一代號，只排一個" do
      original_read = Rails.cache.method(:read)
      allow(Rails.cache).to receive(:read) do |*args, **kw|
        value = original_read.call(*args, **kw)
        sleep 0.05
        value
      end
      started = Concurrent::Array.new

      ids = Array.new(6) { Thread.new { described_class.join_or_start(symbol, nil) { |id| started << id } } }.map(&:value)

      expect(ids.uniq.size).to eq(1)
      expect(started.size).to eq(1)
    end

    describe "#perform 結束就取消登記" do
      let(:svc) { instance_double(BarchartScraperService, fetch_pmcc_short_calls: { status: "no_candidates" }) }

      before { allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc) }

      it "成功之後，下一次查詢重新開始（快取新鮮度由 fresh_for? 另外判斷）" do
        allow(svc).to receive(:fetch_leaps).and_return({ status: "success", errors: [] })
        id, = start

        described_class.perform_now(symbol, id)

        _, started = start
        expect(started.size).to eq(1)
      end

      it "失敗（例外）也一樣取消，失敗結果不會讓後來的人共用" do
        allow(svc).to receive(:fetch_leaps).and_raise(RuntimeError, "boom")
        id, = start

        described_class.perform_now(symbol, id)

        _, started = start
        expect(started.size).to eq(1)
      end

      it "只取消自己的登記：舊 job 晚結束時，不會把新一輪的登記清掉" do
        allow(svc).to receive(:fetch_leaps).and_return({ status: "success", errors: [] })
        Rails.cache.write(described_class.inflight_key(symbol, nil),
                          { job_id: "newer0000000000a", owner: ApplicationJob::PROCESS_TOKEN })

        described_class.perform_now(symbol, "older0000000000b")

        expect(described_class.join_or_start(symbol, nil) { nil }).to eq("newer0000000000a")
      end
    end
  end
end
