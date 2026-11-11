# frozen_string_literal: true

# LEAPS 互動查詢與每日 IV 快照排程之間的互斥（leaps-iv-environment.md P4）。
# 兩者共用 9222 的 Chrome，P0 偵察確認跨程序（Puma ↔ pm2 排程）沒有任何鎖。
#
# PostgreSQL advisory lock，兩種模式：
#   - shared：互動查詢。多個使用者的 LEAPS 查詢照舊可以同時跑（站內另有 ScraperSlots 上限 3）。
#   - exclusive：排程。要等所有互動查詢結束才拿得到；拿到之後新的互動查詢等待。
#     排程逐個標的取鎖、做完就放，互動查詢可以插在兩個標的之間，不會被整段排程擋住。
# 取不到就每 POLL_S 秒重試，最多 wait 秒，逾時拋 Timeout。
#
# 鎖綁在連線上，持鎖期間連線不能還。連線池只有 5 條（Puma 3 執行緒＋背景 job 共用），
# 一次 LEAPS 查詢要好幾分鐘，所以不向連線池借：另開一條獨立的 PG 連線，用完就關。
class LeapsIvCdpLock
  class Timeout < StandardError; end

  KEY    = "leaps_iv_cdp"
  POLL_S = 2

  def self.shared(wait:, label:, logger: Rails.logger, &)
    new(mode: :shared, wait: wait, label: label, logger: logger).hold(&)
  end

  def self.exclusive(wait:, label:, logger: Rails.logger, &)
    new(mode: :exclusive, wait: wait, label: label, logger: logger).hold(&)
  end

  def self.wait_sec = LeapsIvConfig.fetch(:lock_wait_sec)

  def initialize(mode:, wait:, label:, logger:)
    @mode, @wait, @label, @logger = mode, wait, label, logger
  end

  def hold
    conn = self.class.connect
    acquire!(conn)
    begin
      yield
    ensure
      conn.exec_params("SELECT #{unlock_fn}(hashtext($1))", [ KEY ])
    end
  ensure
    conn&.close
  end

  def self.connect
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    return PG.connect(cfg[:url]) if cfg[:url]

    PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: cfg[:username],
               password: cfg[:password])
  end

  private

  def lock_fn   = @mode == :shared ? "pg_try_advisory_lock_shared" : "pg_try_advisory_lock"
  def unlock_fn = @mode == :shared ? "pg_advisory_unlock_shared" : "pg_advisory_unlock"

  def acquire!(conn)
    deadline = monotonic + @wait
    waited   = false
    loop do
      return log_acquired(waited) if conn.exec_params("SELECT #{lock_fn}(hashtext($1))", [ KEY ]).getvalue(0, 0) == "t"

      if monotonic >= deadline
        @logger.warn("[leaps_iv_lock] #{@label}：等 #{@mode} 鎖超過 #{@wait} 秒，放棄")
        raise Timeout, "等待 LEAPS 抓取鎖超過 #{@wait} 秒（另一邊正在使用 Chrome），請稍後再試"
      end
      @logger.info("[leaps_iv_lock] #{@label}：鎖被占用，等待中（#{@mode}）") unless waited
      waited = true
      sleep POLL_S
    end
  end

  def log_acquired(waited)
    @logger.info("[leaps_iv_lock] #{@label}：#{waited ? '等待後' : ''}取得 #{@mode} 鎖")
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
