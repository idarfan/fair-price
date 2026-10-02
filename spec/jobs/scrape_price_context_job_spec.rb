# frozen_string_literal: true

require "rails_helper"

# 排程鎖的壽命必須等於 job 的壽命。原本鎖只靠 3 分鐘 TTL 自己消失，
# job 超過 3 分鐘時輪詢端點會誤以為已經跑完而提早回 ok；單純拉長 TTL 又會讓
# server 重啟時被砍掉的 job 留下一把沒人解的鎖（Async adapter，job 跑在 Rails 程序裡）。
RSpec.describe ScrapePriceContextJob do
  let(:symbol) { "TSTX" }
  let(:svc)    { instance_double(BarchartScraperService) }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  # S4 起 job 會傳 phase: 回呼，讓輪詢端點分辨排隊中與執行中。
  before { allow(BarchartScraperService).to receive(:new).with(symbol, phase: kind_of(Proc)).and_return(svc) }

  describe "排程鎖" do
    it "acquire_lock 成功後 running? 為 true；同一程序第二次 acquire 失敗" do
      expect(described_class.acquire_lock(symbol)).to be(true)
      expect(described_class.running?(symbol)).to be(true)
      expect(described_class.acquire_lock(symbol)).to be(false)
    end

    it "別的程序留下的鎖（server 重啟前的 job）視為無效，可以重新取得" do
      Rails.cache.write(described_class.lock_key(symbol), "dead-process-owner")

      expect(described_class.running?(symbol)).to be(false)
      expect(described_class.acquire_lock(symbol)).to be(true)
      expect(described_class.running?(symbol)).to be(true)
    end

    # 原本 acquire_lock 是「讀 → 判斷 → 寫」，兩個輪詢請求同時進來時，
    # 兩邊都可能在對方寫入前讀到「沒鎖」，各排一個 job。
    # 讀與寫之間刻意插入延遲，把競態窗口撐開到每次都會撞上。
    it "多個執行緒同時搶鎖，只有一個拿得到" do
      original_read = Rails.cache.method(:read)
      allow(Rails.cache).to receive(:read) do |*args, **kw|
        value = original_read.call(*args, **kw)
        sleep 0.05
        value
      end

      results = Array.new(8) { Thread.new { described_class.acquire_lock(symbol) } }.map(&:value)

      expect(results.count(true)).to eq(1)
    end

    it "release_lock 之後 running? 為 false" do
      described_class.acquire_lock(symbol)
      described_class.release_lock(symbol)

      expect(described_class.running?(symbol)).to be(false)
    end
  end

  # 前端輪詢的等待上限由這個值決定（頁面 data-poll-timeout-ms）。
  # 原本前端寫死 24 次 × 5 秒＝2 分鐘，job 最壞要跑到兩支爬蟲各自逾時加寬限期，
  # 前端會先放棄、顯示「逾時」，而 job 其實還在跑。
  describe ".poll_budget_s" do
    it "涵蓋兩支爬蟲逾時加上砍程序的寬限期，前端不會比 job 先放棄" do
      worst_job = BarchartScraperService::SCRAPER_TIMEOUTS_S.values_at("volap", "price_history").sum +
                  (2 * TimedCapture::DEFAULT_KILL_GRACE_S)

      expect(described_class.poll_budget_s).to be > worst_job
    end
  end

  # 並行化 S4：S2 之後價格情境抓取可能排在 LEAPS（3–5 分鐘）後面。前端的逾時上限
  # （poll_budget_s）只涵蓋爬蟲真的在跑的時間，排隊時間要能跟它分開。
  describe "抓取階段（排隊中／執行中）" do
    it "爬蟲回報的階段寫進快取，讀得回來" do
      phase_cb = nil
      allow(BarchartScraperService).to receive(:new).with(symbol, phase: kind_of(Proc)) do |_, phase:|
        phase_cb = phase
        svc
      end
      seen = []
      allow(svc).to receive(:fetch_volap) do
        phase_cb.call(:queued)
        seen << described_class.phase(symbol)
        phase_cb.call(:running)
        seen << described_class.phase(symbol)
        { status: "success" }
      end
      allow(svc).to receive(:fetch_price_history).and_return({ status: "success" })

      described_class.perform_now(symbol)

      expect(seen).to eq(%w[queued running])
    end

    it "job 結束（含例外）就清掉階段" do
      allow(svc).to receive(:fetch_volap) do
        described_class.record_phase(symbol, :running)
        raise IOError, "scraper blew up"
      end
      allow(svc).to receive(:fetch_price_history).and_return({ status: "success" })

      described_class.perform_now(symbol)

      expect(described_class.phase(symbol)).to be_nil
    end
  end

  describe "#perform" do
    it "跑完就解鎖，並寫入結果" do
      allow(svc).to receive_messages(fetch_volap: { status: "success" },
                                     fetch_price_history: { status: "success" })
      described_class.acquire_lock(symbol)

      described_class.perform_now(symbol)

      expect(described_class.running?(symbol)).to be(false)
      expect(Rails.cache.read(described_class.cache_key(symbol))[:status]).to eq("success")
    end

    it "跑超過 3 分鐘時鎖仍然在（不再靠 TTL 判斷是否跑完）" do
      described_class.acquire_lock(symbol)
      allow(svc).to receive(:fetch_volap) do
        travel 5.minutes
        expect(described_class.running?(symbol)).to be(true)
        { status: "success" }
      end
      allow(svc).to receive(:fetch_price_history).and_return({ status: "success" })

      described_class.perform_now(symbol)

      expect(described_class.running?(symbol)).to be(false)
    end

    it "爬蟲炸到 job 外層也一樣解鎖" do
      allow(svc).to receive_messages(fetch_volap: { status: "success" },
                                     fetch_price_history: { status: "success" })
      allow(Rails.cache).to receive(:write).and_call_original
      allow(Rails.cache).to receive(:write)
        .with(described_class.cache_key(symbol), anything, anything)
        .and_raise(IOError, "disk full")
      described_class.acquire_lock(symbol)

      expect { described_class.perform_now(symbol) }.to raise_error(IOError)
      expect(described_class.running?(symbol)).to be(false)
    end
  end
end
