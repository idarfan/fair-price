# frozen_string_literal: true

namespace :iv do
  desc "抓取所有 watchlist ticker 的當日 ATM IV 快照"
  task daily_snapshot: :environment do
    puts "[iv:daily_snapshot] 開始執行，#{Time.current.in_time_zone("Eastern Time (US & Canada)").strftime("%Y-%m-%d %H:%M ET")}"
    result = WatchedTickersService.daily_fetch_all
    puts "[iv:daily_snapshot] 完成 — 成功: #{result[:success]} / 跳過: #{result[:skipped]} / 失敗: #{result[:failures]} / 總計: #{result[:total]}"
    exit 1 if result[:failures] > 0 && result[:success] == 0
  end

  desc "抓取所有 watchlist ticker 的當日 25-delta Skew 快照"
  task skew_snapshot: :environment do
    puts "[iv:skew_snapshot] 開始執行，#{Time.current.in_time_zone("Eastern Time (US & Canada)").strftime("%Y-%m-%d %H:%M ET")}"
    tickers = (IvWatchlist.active.pluck(:symbol) + WatchedTicker.active.pluck(:ticker)).uniq
    success = 0
    failures = 0
    tickers.each do |ticker|
      result = SkewSnapshotService.fetch_and_store(ticker)
      puts "[iv:skew_snapshot] ✅ #{ticker} skew_pts=#{result[:skew_pts]} rank=#{result[:skew_rank]}"
      success += 1
    rescue => e
      warn "[iv:skew_snapshot] ❌ #{ticker} 失敗 — #{e.message}"
      failures += 1
    end
    puts "[iv:skew_snapshot] 完成 — 成功: #{success} / 失敗: #{failures} / 總計: #{tickers.size}"
    exit 1 if failures > 0 && success == 0
  end

  desc "補抓單一 ticker 當日 IV（用法：rake iv:backfill[AAPL]）"
  task :backfill, [:ticker] => :environment do |_t, args|
    ticker = args[:ticker].to_s.upcase.strip
    if ticker.blank?
      warn "請指定 ticker，例如：rake iv:backfill[AAPL]"
      exit 1
    end

    puts "[iv:backfill] 補抓 #{ticker}…"
    begin
      data = IvSidecarService.fetch_atm_iv(ticker)
      today = Date.current
      if IvDailySnapshot.exists?(ticker: ticker, snapshot_date: today)
        puts "[iv:backfill] #{ticker} 今日快照已存在，跳過"
      else
        IvDailySnapshot.create!(
          ticker:        ticker,
          snapshot_date: today,
          atm_iv:        data[:atm_iv],
          atm_strike:    data[:atm_strike],
          current_price: data[:current_price]
        )
        WatchedTicker.find_by(ticker: ticker)&.update!(last_fetched_at: Time.current)
        puts "[iv:backfill] ✅ #{ticker} 快照已寫入 — atm_iv=#{data[:atm_iv]}"
      end
    rescue => e
      warn "[iv:backfill] ❌ #{ticker} 失敗 — #{e.message}"
      exit 1
    end
  end
end
