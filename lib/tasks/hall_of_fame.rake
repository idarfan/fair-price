# frozen_string_literal: true

namespace :hall_of_fame do
  desc "由 config/hall_of_fame.yml 同步名人堂名單至 hof_officials（冪等）"
  task seed_officials: :environment do
    officials = HallOfFame::OfficialSeeder.new.call
    puts "hall_of_fame:seed_officials 同步 #{officials.size} 位；hof_officials 共 #{HallOfFame::Official.count} 筆"
  end

  desc "同步 House 年度索引（當年＋前一年）至 hof_filings（條件式請求，冪等）"
  task sync_house_index: :environment do
    run = HallOfFame::HouseIndexSync.new.call
    puts "hall_of_fame:sync_house_index run##{run.id} 新增 #{run.new_filings_count} 筆，錯誤 #{run.error_count}"
    puts run.error_log if run.error_log.present?
  end
end
