# frozen_string_literal: true

require "open3"

# 執行 Python 期權快照蒐集器。
#
# 這段原本直接跑在 Api::V1::TrackedTickersController#collect 的 request 週期裡，
# 沒有 timeout：爬蟲一卡住，那條 Puma thread 就永久佔用。RAILS_MAX_THREADS 預設 5，
# 五個請求就足以讓整站沒有回應。改成背景 job + 硬性 timeout，狀態比照
# BcvsFetchChainJob 寫進 Rails.cache 給前端輪詢。
class CollectOptionSnapshotsJob < ApplicationJob
  TIMEOUT = 5.minutes
  CACHE_TTL = 10.minutes

  def self.cache_key(job_id) = "collect_snapshots_job_#{job_id}"

  def perform(tracked_ticker_id, job_id)
    ticker = TrackedTicker.find(tracked_ticker_id)

    if run_collector(ticker.symbol)
      write_status(job_id, status: "success", symbol: ticker.symbol)
    else
      write_status(job_id, status: "error", symbol: ticker.symbol,
                          errors: [ "#{ticker.symbol} 期權資料抓取失敗，請確認 Python 環境" ])
    end
  rescue ActiveRecord::RecordNotFound
    write_status(job_id, status: "error", errors: [ "追蹤代號已不存在" ])
  rescue Timeout::Error
    Rails.logger.error("[CollectOptionSnapshots] #{tracked_ticker_id} 逾時（#{TIMEOUT.inspect}）")
    write_status(job_id, status: "error", errors: [ "抓取逾時，請稍後再試" ])
  rescue StandardError => e
    Rails.logger.error("[CollectOptionSnapshots] #{e.class}: #{e.message}")
    write_status(job_id, status: "error", errors: [ "抓取失敗，請稍後再試" ])
  end

  private

  # 回傳 true 代表 Python 行程正常結束。逾時就砍掉子行程，不留孤兒。
  def run_collector(symbol)
    python = Rails.root.join("scripts/venv/bin/python3").to_s
    script = Rails.root.join("scripts/options_collector.py").to_s

    Open3.popen2e(python, script, "--symbols", symbol, "--force") do |stdin, out, wait_thr|
      stdin.close

      unless wait_thr.join(TIMEOUT.to_i)
        Process.kill("KILL", wait_thr.pid) rescue nil
        raise Timeout::Error, "options_collector.py 超過 #{TIMEOUT.to_i} 秒未結束"
      end

      output = out.read.to_s
      Rails.logger.info("[CollectOptionSnapshots] #{symbol} exit=#{wait_thr.value.exitstatus} #{output.last(500)}")
      wait_thr.value.success?
    end
  end

  def write_status(job_id, **payload)
    Rails.cache.write(self.class.cache_key(job_id), payload.compact, expires_in: CACHE_TTL)
  end
end
