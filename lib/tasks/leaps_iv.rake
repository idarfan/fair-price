# frozen_string_literal: true

# LEAPS IV 環境每日快照（leaps-iv-environment.md P4）。入口是 bin/leaps_iv_snapshot（pm2 leaps-iv-snapshot）。
namespace :leaps_iv do
  desc "每日 LEAPS IV 快照：watchlist ∪ 近 30 天查詢過的標的，逐一抓 IV 曲面＋Barchart IV 歷史"
  task snapshot: :environment do
    runner = LeapsIvSnapshotRunner.new
    # P7.1：pm2 cron 提早觸發（cron_restart 是 pm2 傳進來的排程字串；手動執行沒有）
    if runner.early_fire?(ENV["cron_restart"])
      puts "pm2 cron 提早觸發，略過"
      next
    end

    results = runner.run
    puts results.map { |sym, r| "#{sym}=#{r}" }.join(" ")
    exit 1 if results.any? && results.values.all?(:error)
  end

  desc "手動回補單一標的的 Barchart IV 歷史（2Y）"
  task :backfill, [ :symbol ] => :environment do |_, args|
    abort "用法：bin/leaps_iv_snapshot --backfill SYMBOL" if args[:symbol].blank?

    result = LeapsIvSnapshotRunner.new.backfill(args[:symbol])
    puts "#{args[:symbol].upcase}=#{result}"
    exit 1 unless result == :ok
  end
end
