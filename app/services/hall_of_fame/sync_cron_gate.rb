# frozen_string_literal: true

module HallOfFame
  # pm2 cron 提早觸發防護（hall-of-fame-spec.md P4.1-2）。
  #
  # 直接沿用 leaps-iv-environment P7.1 的 LeapsIvCronGuard 與 LeapsIvSnapshotRunner#early_fire? 的行為，
  # 不重新設計：
  # - 只看 pm2 傳給子程序的環境變數 cron_restart；沒有（手動執行）一律照跑。
  # - 現在離下一次排定時間比離上一次近 → 提早觸發，略過；延後觸發只要沒晚過中點照常執行。
  # - cron 字串無法判斷 → 記 warn 後照跑，寧可多跑也不讓排程整個停掉。
  class SyncCronGate
    PREFIX = "[hall_of_fame:sync_house]"

    def initialize(out: $stdout, logger: Rails.logger)
      @out    = out
      @logger = logger
    end

    # 提早觸發回 true（呼叫端應略過整輪），並印一行略過訊息到 stdout（pm2 out log）與 Rails log。
    def early_fire?(cron, now: Time.now.utc)
      return false if cron.blank?

      guard = LeapsIvCronGuard.new(cron)
      return false unless guard.early?(now)

      message = "#{PREFIX} pm2 cron 提早觸發，略過：現在 #{now.utc.iso8601}，" \
                "下一次排定 #{guard.next_at(now).iso8601}（cron #{cron}，UTC）"
      @out.puts(message)
      @logger.info(message)
      true
    rescue LeapsIvCronGuard::Unsupported => e
      @logger.warn("#{PREFIX} cron #{cron.inspect} 無法判斷提早觸發，照常執行：#{e.message}")
      false
    end
  end
end
