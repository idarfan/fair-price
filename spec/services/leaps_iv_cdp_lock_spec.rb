# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P4：互動查詢（shared）與每日 IV 快照排程（exclusive）的互斥。
# 用測試資料庫的真實 advisory lock 與執行緒驗證，不 stub。
RSpec.describe LeapsIvCdpLock do
  let(:log)    { StringIO.new }
  let(:logger) { Logger.new(log) }

  before { stub_const("LeapsIvCdpLock::POLL_S", 0.05) }

  def hold_in_thread(mode, ready:, release:)
    Thread.new do
      described_class.public_send(mode, wait: 5, label: "背景 #{mode}", logger: logger) do
        ready << true
        release.pop
      end
    end
  end

  it "多個互動查詢（shared）可以同時持鎖" do
    ready, release = Queue.new, Queue.new
    t = hold_in_thread(:shared, ready: ready, release: release)
    ready.pop

    ran = false
    described_class.shared(wait: 1, label: "第二個查詢", logger: logger) { ran = true }
    expect(ran).to be true
  ensure
    release << true
    t&.join
  end

  it "互動查詢持鎖時，排程（exclusive）等待；等超過上限拋 Timeout，區塊不執行" do
    ready, release = Queue.new, Queue.new
    t = hold_in_thread(:shared, ready: ready, release: release)
    ready.pop

    ran = false
    expect { described_class.exclusive(wait: 0.3, label: "排程 TSM", logger: logger) { ran = true } }
      .to raise_error(LeapsIvCdpLock::Timeout, /超過/)
    expect(ran).to be false
    expect(log.string).to include("排程 TSM：鎖被占用，等待中（exclusive）", "放棄")
  ensure
    release << true
    t&.join
  end

  it "排程持鎖時，互動查詢等待；排程做完放鎖後取得（log 記錄等待）" do
    ready, release = Queue.new, Queue.new
    t = hold_in_thread(:exclusive, ready: ready, release: release)
    ready.pop

    waiter = Thread.new { described_class.shared(wait: 5, label: "LEAPS 查詢 TSM", logger: logger) { :done } }
    sleep 0.3
    expect(waiter).to be_alive
    release << true

    expect(waiter.value).to eq(:done)
    expect(log.string).to include("LEAPS 查詢 TSM：鎖被占用，等待中（shared）", "LEAPS 查詢 TSM：等待後取得 shared 鎖")
  ensure
    t&.join
  end

  it "區塊拋例外也會放鎖，下一個 exclusive 立刻取得" do
    expect { described_class.shared(wait: 1, label: "出錯的查詢", logger: logger) { raise "boom" } }.to raise_error("boom")

    ran = false
    described_class.exclusive(wait: 0.2, label: "排程", logger: logger) { ran = true }
    expect(ran).to be true
  end

  it "不向 ActiveRecord 連線池借連線（持鎖期間連線池不少一條）" do
    pool = ActiveRecord::Base.connection_pool
    busy = nil
    described_class.shared(wait: 1, label: "查詢", logger: logger) { busy = pool.stat[:busy] }
    expect(busy).to eq(pool.stat[:busy])
  end

  it "等候上限讀 config/leaps_iv.yml 的 lock_wait_sec" do
    expect(described_class.wait_sec).to eq(900)
  end
end
