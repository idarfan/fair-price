# frozen_string_literal: true

require "rails_helper"

# 所有 Barchart 爬蟲共用一個 Chrome（9222）。同時開太多分頁會把它壓垮，
# 所以同時執行的爬蟲數有明確上限。
#
# 原本沒有明確上限：Async adapter 執行緒池 max_threads 取 RAILS_MAX_THREADS，
# production 未設定時預設 5（Puma 預設 3，兩者不同），背景抓取最多同時 5 個。
# （S2 送審時誤寫成 3，2026-10-02 更正。）
RSpec.describe ScraperSlots do
  it "上限是明確的常數 3，不跟 RAILS_MAX_THREADS 連動" do
    expect(described_class::MAX_CONCURRENT).to eq(3)
  end

  it "同時進來的人再多，同一時間最多 MAX_CONCURRENT 個在跑，其餘排隊，最後全部跑完" do
    slots   = described_class.new(3)
    running = Concurrent::AtomicFixnum.new(0)
    peak    = Concurrent::AtomicFixnum.new(0)

    threads = Array.new(8) do
      Thread.new do
        slots.with_slot do
          now = running.increment
          peak.update { |p| [ p, now ].max }
          sleep 0.05
          running.decrement
          :done
        end
      end
    end

    expect(threads.map(&:value)).to all(eq(:done))
    expect(peak.value).to eq(3)
  end

  it "區塊丟例外也會歸還名額" do
    slots = described_class.new(1)

    expect { slots.with_slot { raise IOError, "boom" } }.to raise_error(IOError)
    expect(slots.with_slot { :got_it }).to eq(:got_it)
  end

  it ".with_slot 走全站共用的那一組名額" do
    expect(described_class.instance).to be(described_class::INSTANCE)
    expect(described_class.with_slot { :ok }).to eq(:ok)
  end
end
