# frozen_string_literal: true

# 排程資料的新鮮度檢查。
#
# 存在的理由：2026-08-30 發現 pm2 daemon 沒有以 TZ=UTC 啟動，導致 iv-* 排程
# 全部早 8 小時，intraday 每次都落在非交易時段而跳過——skew_rank_intradays
# 從 2026-05-19 起就沒有新資料，**靜默了 3.5 個月**。
#
# 排程壞掉不會拋例外、不會有紅字，只會「沒有新資料」。唯一可靠的偵測方式
# 就是主動比對「最新一筆的時間」與「預期的更新頻率」。
#
# 用法：
#   bundle exec rake ops:freshness        # 有過期就 exit 1
#   bin/audit freshness
namespace :ops do
  # [人類看得懂的名稱, 關聯, 時間欄位, 容許落後幾個「交易日」]
  #
  # 容許值以交易日計算（跳過週末），因為這些排程都只在美股交易日跑。
  # 抓得寬一點是刻意的——這裡要抓的是「壞掉好幾週沒人發現」，
  # 不是「今天這一次沒跑到」，太敏感會變成沒人看的雜訊。
  CHECKS = [
    { label: "選擇權每日快照",   model: "OptionSnapshot",     column: :snapped_at,     max_trading_days: 3 },
    { label: "IV 每日快照",       model: "IvDailySnapshot",    column: :created_at,     max_trading_days: 3 },
    { label: "Skew 每日排名",     model: "SkewRankDaily",      column: :snapshot_date,  max_trading_days: 3 },
    { label: "Skew 盤中排名",     model: "SkewRankIntraday",   column: :snapshot_time,  max_trading_days: 3 },
    { label: "選擇權資金流",      model: "OptionsFlowTrade",   column: :snapshot_date,  max_trading_days: 5 }
  ].freeze

  # 從今天往回數 n 個交易日（只跳週末，不處理美股假日——寬容度已經留夠）。
  def self.trading_days_ago(count)
    date = Date.current
    remaining = count
    while remaining.positive?
      date -= 1
      remaining -= 1 unless date.saturday? || date.sunday?
    end
    date
  end

  desc "檢查排程產出的資料是否還在更新（排程靜默壞掉時唯一的偵測手段）"
  task freshness: :environment do
    rows = []
    stale = 0

    CHECKS.each do |check|
      klass = check[:model].safe_constantize
      unless klass
        rows << [ check[:label], "—", "model 不存在", :error ]
        stale += 1
        next
      end

      latest = klass.maximum(check[:column])
      cutoff = trading_days_ago(check[:max_trading_days])

      if latest.nil?
        rows << [ check[:label], "（無資料）", "整張表是空的", :error ]
        stale += 1
        next
      end

      latest_date = latest.respond_to?(:to_date) ? latest.to_date : latest
      behind_days = (Date.current - latest_date).to_i

      if latest_date < cutoff
        rows << [ check[:label], latest.to_s, "落後 #{behind_days} 天（容許 #{check[:max_trading_days]} 個交易日）", :stale ]
        stale += 1
      else
        rows << [ check[:label], latest.to_s, "正常", :ok ]
      end
    end

    # 中日韓字元在終端機是雙寬，String#length 會少算——用顯示寬度補空白，
    # 否則欄位會歪掉（純 ASCII 的表格程式碼在這裡會誤導）。
    display_width = ->(str) { str.each_char.sum { |c| c.bytesize > 2 ? 2 : 1 } }
    label_width   = rows.map { |r| display_width.call(r[0]) }.max
    stamp_width   = rows.map { |r| display_width.call(r[1]) }.max

    rows.each do |label, latest, note, status|
      mark = { ok: "✓", stale: "✗", error: "✗" }.fetch(status)
      pad  = ->(str, target) { str + (" " * [ target - display_width.call(str), 0 ].max) }
      puts "  #{mark} #{pad.call(label, label_width)}  #{pad.call(latest, stamp_width)}  #{note}"
    end

    if stale.positive?
      puts
      puts "  #{stale} 項資料已過期。排查順序："
      puts "    1. pm2 daemon 的時區：./scripts/fix-pm2-timezone.sh --check"
      puts "    2. systemd timer：systemctl --user list-timers --all"
      puts "    3. 對應 job 的 log：pm2 logs <name> --lines 30 --nostream"
      abort
    end

    puts
    puts "  全部 #{rows.size} 項都在更新中。"
  end
end
