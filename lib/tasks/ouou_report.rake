# frozen_string_literal: true

namespace :ouou do
  desc "發送歐歐每日盤前報告到 Telegram（歐歐是隻黑魯魯的發財貓群組）"
  task pre_market: :environment do
    puts "[ouou:pre_market] 開始執行，#{Time.current.in_time_zone("Eastern Time (US & Canada)").strftime("%Y-%m-%d %H:%M ET")}"
    result = OuouPreMarketService.new.call
    if result
      puts "✅ 歐歐盤前報告已發送"
    else
      warn "❌ 發送失敗，請檢查 Rails log"
      exit 1
    end
  end
end
