# frozen_string_literal: true

# leaps_call_chain_fetcher_spec 用的 sidecar 替身（2026-09-26 從 spec 內移出：
# 定義在 example group 裡的 class 會洩漏成全域常數，RuboCop RSpec/LeakyConstantDeclaration）。
#
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
