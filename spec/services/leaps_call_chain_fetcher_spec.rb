# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P1。sidecar 一律以 FakeRunner 取代，不連 Barchart。
#
# 「sidecar 被呼叫 N 次」以「到期日 chain 的抓取次數」計（規格案例 7、11 的說法是
# 「sidecar 只被要求抓那 1 個到期日」）；到期日清單的抓取另外斷言。
RSpec.describe LeapsCallChainFetcher do
  # 模擬 sidecar：每個階段宣告一個「耗時」，超過 fetcher 傳進來的 timeout 就視為
  # 停滯（真的 runner 會在 timeout 秒時終止程序並丟出 Stalled）。
  class LeapsChainFakeRunner
    attr_reader :chain_calls, :expiration_calls, :timeouts

    def initialize(expirations:, chains: {}, expirations_status: "success", durations: {}, delay: 0)
      @expirations = expirations
      @chains = chains
      @expirations_status = expirations_status
      @durations = durations
      @delay = delay
      @chain_calls = []
      @expiration_calls = 0
      @timeouts = []
      @mutex = Mutex.new
    end

    def call(kind, symbol, *args, timeout:)
      @mutex.synchronize { @timeouts << timeout }
      case kind
      when :expirations
        @mutex.synchronize { @expiration_calls += 1 }
        return { "status" => @expirations_status } unless @expirations_status == "success"

        { "status" => "success", "expirations" => @expirations, "underlying_price" => 139.54 }
      when :chain
        expiry = args.first
        @mutex.synchronize { @chain_calls << expiry }
        sleep(@delay) if @delay.positive?
        if @durations.fetch(expiry, 0) > timeout
          raise LeapsCallChainFetcher::Stalled.new("讀取 #{expiry[0, 10]} chain", timeout)
        end

        { "status" => "success", "rows" => @chains.fetch(expiry), "underlying_price" => 139.54 }
      end
    end
  end

  def leaps_expiry(months_ahead)
    "#{(Date.current + months_ahead.months).strftime('%Y-%m-%d')}-m"
  end

  let(:stall) { described_class::STALL_TIMEOUT }
  let(:exp_a) { leaps_expiry(14) }
  let(:exp_b) { leaps_expiry(16) }
  let(:exp_c) { leaps_expiry(20) }
  let(:short_expiry) { leaps_expiry(2) }
  let(:rows) do
    [
      { "strike" => 100, "bid" => 40.1, "ask" => 41.3, "last" => 40.5, "delta" => 0.82 },
      { "strike" => 210, "bid" => 0, "ask" => 0, "last" => 11.2, "delta" => 0.3 }
    ]
  end

  def runner_for(expiries, **opts)
    LeapsChainFakeRunner.new(expirations: [ short_expiry, *expiries ], chains: expiries.index_with { rows }, **opts)
  end

  def fetch(runner, ticker = "ORCL", **kwargs)
    described_class.new(ticker, runner: runner).call(**kwargs)
  end

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  describe "1–3 快取" do
    it "1. 快取未命中：抓 1 次並寫入快取" do
      runner = runner_for([ exp_a ])
      result = fetch(runner)

      expect(result[:status]).to eq(:ok)
      expect(runner.chain_calls).to eq([ exp_a ])
      expect(runner.expiration_calls).to eq(1)
      expect(BcvsChainSnapshot.for_symbol_and_expiration("ORCL", exp_a)).to exist
    end

    it "2. 29 分鐘內再查：不呼叫 sidecar" do
      fetch(runner_for([ exp_a ]))
      travel 29.minutes do
        runner = runner_for([ exp_a ])
        result = fetch(runner)
        expect(result[:status]).to eq(:ok)
        expect(runner.chain_calls).to be_empty
        expect(runner.expiration_calls).to eq(0)
      end
    end

    it "3. 31 分鐘後再查：再抓 1 次" do
      fetch(runner_for([ exp_a ]))
      travel 31.minutes do
        runner = runner_for([ exp_a ])
        fetch(runner)
        expect(runner.chain_calls).to eq([ exp_a ])
      end
    end
  end

  describe "4–6 停滯判定" do
    it "4. 第 2 個到期日之後停滯：回傳 error、原因含停住的階段、不寫入快取" do
      runner = runner_for([ exp_a, exp_b, exp_c ], durations: { exp_c => stall + 1 })
      result = fetch(runner)

      expect(result[:status]).to eq(:error)
      expect(result[:code]).to eq(:stalled)
      expect(result[:message]).to include("讀取 #{exp_c[0, 10]} chain").and include("#{stall} 秒沒有回應")
      expect(BcvsChainSnapshot.where(symbol: "ORCL")).not_to exist
    end

    it "5. 慢但有進度：總耗時超過 STALL_TIMEOUT × 3，但每段都在時限內 → 成功" do
      expiries = [ exp_a, exp_b, exp_c, leaps_expiry(24) ]
      durations = expiries.index_with { stall - 1 }
      runner = runner_for(expiries, durations: durations)

      result = fetch(runner)

      expect(durations.values.sum).to be > stall * 3
      expect(result[:status]).to eq(:ok)
      expect(result[:expirations].size).to eq(4)
    end

    it "6. 每一段都以設定常數 STALL_TIMEOUT 作為時限" do
      runner = runner_for([ exp_a, exp_b ])
      fetch(runner)
      expect(runner.timeouts).to all(eq(described_class::STALL_TIMEOUT))
    end
  end

  describe "7 部分快取與進度" do
    it "3 個到期日中 1 個過期：只抓那 1 個，進度 N = 1" do
      fetch(runner_for([ exp_a, exp_b, exp_c ]))
      BcvsChainSnapshot.for_symbol_and_expiration("ORCL", exp_b).update_all(scraped_at: 31.minutes.ago)

      runner = runner_for([ exp_a, exp_b, exp_c ])
      result = fetch(runner)

      expect(runner.chain_calls).to eq([ exp_b ])
      expect(result[:status]).to eq(:ok)
      expect(result[:expirations].map { |e| e[:expiry] }).to eq([ exp_a, exp_b, exp_c ])
      progress = described_class.progress("ORCL")
      expect(progress).to include(total: 1, done: 1, state: "done")
    end
  end

  describe "8 同一標的同時查詢" do
    self.use_transactional_tests = false

    after do
      BcvsChainSnapshot.where(symbol: "ORCL").delete_all
      BcvsExpirationSnapshot.where(symbol: "ORCL").delete_all
    end

    it "兩個執行緒同時查 ORCL：sidecar 只抓 1 次，兩邊結果相同" do
      runner = runner_for([ exp_a ], delay: 1)
      results = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { fetch(runner) }
        end
      end.map(&:value)

      expect(runner.chain_calls).to eq([ exp_a ])
      expect(results.map { |r| r[:status] }).to eq([ :ok, :ok ])
      expect(results.first[:expirations]).to eq(results.last[:expirations])
    end
  end

  describe "9 查無代號、沒有 LEAPS" do
    it "查無代號" do
      result = fetch(LeapsChainFakeRunner.new(expirations: [], expirations_status: "symbol_not_found"), "ZZZZQ")
      expect(result).to include(status: :error, code: :symbol_not_found, message: "查無股票代號 ZZZZQ")
    end

    it "完全沒有選擇權" do
      result = fetch(LeapsChainFakeRunner.new(expirations: [], expirations_status: "no_options"), "BRK.A")
      expect(result).to include(status: :error, code: :no_leaps, message: "BRK.A 沒有適合的 LEAPS 標的")
    end

    it "有選擇權但沒有 DTE ≥ 364 的到期日" do
      result = fetch(LeapsChainFakeRunner.new(expirations: [ short_expiry ]))
      expect(result).to include(status: :error, code: :no_leaps, message: "ORCL 沒有適合的 LEAPS 標的")
    end
  end

  describe "10 代號正規化" do
    it "` orcl ` 查詢與快取 key 都用 ORCL" do
      runner = runner_for([ exp_a ])
      result = fetch(runner, " orcl ")

      expect(result[:symbol]).to eq("ORCL")
      expect(BcvsChainSnapshot.for_symbol_and_expiration("ORCL", exp_a)).to exist
      expect(BcvsExpirationSnapshot.where(symbol: "ORCL")).to exist
    end
  end

  describe "11 選單變動遇到過期快取" do
    it "所選到期日是 31 分鐘前：只抓這 1 個，其他不重抓" do
      fetch(runner_for([ exp_a, exp_b, exp_c ]))
      travel 31.minutes do
        runner = runner_for([ exp_a, exp_b, exp_c ])
        result = fetch(runner, only_expiry: exp_b)

        expect(runner.chain_calls).to eq([ exp_b ])
        expect(runner.expiration_calls).to eq(0)
        expect(result[:status]).to eq(:ok)
      end
    end
  end

  describe "回傳內容" do
    it "履約價、報價、delta 皆為 BigDecimal，並附抓取時間與現價" do
      result = fetch(runner_for([ exp_a ]))
      calls = result[:expirations].first[:calls]

      expect(calls.first).to include(strike: BigDecimal("100"), bid: BigDecimal("40.1"),
                                     ask: BigDecimal("41.3"), last: BigDecimal("40.5"), delta: BigDecimal("0.82"))
      expect(calls.last).to include(bid: BigDecimal("0"), ask: BigDecimal("0"), last: BigDecimal("11.2"))
      expect(result[:spot]).to eq(BigDecimal("139.54"))
      expect(result[:expirations].first[:fetched_at]).to be_within(5.seconds).of(Time.current)
    end
  end
end

RSpec.describe LeapsCallChainFetcher::SidecarRunner do
  it "超過時限就終止程序並丟出 Stalled（階段名稱與秒數寫在訊息裡）" do
    runner = described_class.new(command: ->(*) { [ "ruby", "-e", "sleep 10" ] })
    started = Time.current

    expect { runner.call(:chain, "ORCL", "2028-01-21-m", timeout: 1) }
      .to raise_error(LeapsCallChainFetcher::Stalled, /讀取 2028-01-21 chain 超過 1 秒沒有回應/)
    expect(Time.current - started).to be < 5
  end

  it "正常結束時回傳解析後的 JSON" do
    runner = described_class.new(command: ->(*) { [ "ruby", "-e", 'print %q({"status":"success","rows":[]})' ] })
    expect(runner.call(:chain, "ORCL", "2028-01-21-m", timeout: 5)).to eq("status" => "success", "rows" => [])
  end
end
