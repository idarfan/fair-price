# frozen_string_literal: true

class WatchedTickersService
  def self.add(ticker)
    ticker = ticker.to_s.upcase.strip
    record = WatchedTicker.find_or_initialize_by(ticker: ticker)
    record.active    = true
    record.added_at ||= Time.current
    record.save!
    record
  end

  def self.remove(ticker)
    WatchedTicker.find_by(ticker: ticker.to_s.upcase.strip)&.update!(active: false)
  end

  def self.daily_fetch_all
    tickers  = WatchedTicker.active.pluck(:ticker)
    success  = 0
    skipped  = 0
    failures = 0

    tickers.each do |ticker|
      today = Date.current

      if IvDailySnapshot.exists?(ticker: ticker, snapshot_date: today)
        Rails.logger.info "[IvDaily] #{ticker}: skipped (snapshot exists)"
        skipped += 1
        next
      end

      begin
        data = IvSidecarService.fetch_atm_iv(ticker)

        IvDailySnapshot.create!(
          ticker:        ticker,
          snapshot_date: today,
          atm_iv:        data[:atm_iv],
          atm_strike:    data[:atm_strike],
          current_price: data[:current_price]
        )

        WatchedTicker.find_by(ticker: ticker)&.update!(last_fetched_at: Time.current)
        Rails.logger.info "[IvDaily] #{ticker}: saved atm_iv=#{data[:atm_iv]}"
        success += 1
      rescue => e
        Rails.logger.error "[IvDaily] #{ticker}: FAILED — #{e.message}"
        failures += 1
      end
    end

    { success: success, skipped: skipped, failures: failures, total: tickers.size }
  end
end
