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

  desc "同步 OGE 行政高層公開申報清單至 hof_filings（Index view 條件式請求，有變動才查 REST API）"
  task sync_oge_index: :environment do
    run = HallOfFame::OgeIndexSync.new.call
    puts "hall_of_fame:sync_oge_index run##{run.id} 新增 #{run.new_filings_count} 筆，錯誤 #{run.error_count}"
    puts run.error_log if run.error_log.present?
  end

  desc "下載並解析 parse_status=pending 的 House PDF（PTR→hof_transactions、年報→hof_holdings）"
  task parse_house_pdfs: :environment do
    summary = HallOfFame::HousePdfParse.new.call
    puts "hall_of_fame:parse_house_pdfs #{summary.counts.sort.map { |s, n| "#{s} #{n}" }.join('、').presence || '無 pending'}"
    puts summary.errors if summary.errors.any?
  end

  desc "期權列解析＋口數／權利金反推（Barchart DOM／Black-Scholes），寫入 hof_option_details"
  task analyze_options: :environment do
    run = HallOfFame::OptionAnalysis.new.call
    sources = HallOfFame::OptionDetail.group(:premium_source).count.map { |s, n| "#{s || '無'} #{n}" }.join("、")
    puts "hall_of_fame:analyze_options run##{run.id} 錯誤 #{run.error_count}；premium_source：#{sources}"
    puts run.error_log if run.error_log.present?
  end

  desc "每日排程（P4）：House 索引同步 → 解析 pending PDF → 期權分析；任一步失敗不中斷後續，結束碼 1"
  task sync_house: :environment do
    result = HallOfFame::HouseDailySync.new.call
    result.runs.each do |kind, run|
      puts "hall_of_fame:sync_house #{kind} run##{run.id} 錯誤 #{run.error_count}"
      puts run.error_log if run.error_log.present?
    end
    next if result.ok?

    warn result.failures
    exit 1
  end

  desc "把 parse_status=failed 的 House filing 改回 pending 並重新解析（修好程式／環境錯誤後手動執行）"
  task retry_failed_house_pdfs: :environment do
    reset = HallOfFame::Filing.where(source: HallOfFame::HouseIndexSync::SOURCE, parse_status: "failed")
                              .update_all(parse_status: "pending", parse_error: nil, updated_at: Time.current)
    puts "hall_of_fame:retry_failed_house_pdfs 改回 pending #{reset} 筆"
    Rake::Task["hall_of_fame:parse_house_pdfs"].invoke
  end
end
