# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "hall_of_fame:sync_house", type: :task do
  let(:task)    { Rake::Task["hall_of_fame:sync_house"] }
  let(:service) { instance_double(HallOfFame::HouseDailySync) }
  let(:run)     { create(:hof_sync_run, kind: "pdf_parse", error_count: 1, error_log: "本次處理：failed 1") }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("hall_of_fame:sync_house")
    task.reenable
    allow(HallOfFame::HouseDailySync).to receive(:new).and_return(service)
  end

  it "prints each run and exits 0 when every step finished" do
    allow(service).to receive(:call).and_return(HallOfFame::HouseDailySync::Result.new(runs: { "pdf_parse" => run }, failures: []))

    expect { task.invoke }.to output(/pdf_parse run##{run.id} 錯誤 1\n本次處理：failed 1/).to_stdout
  end

  it "exits 1 when a step raised" do
    allow(service).to receive(:call).and_return(HallOfFame::HouseDailySync::Result.new(runs: {}, failures: [ "index：HTTP 503" ]))

    expect { task.invoke }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }.and output(/index：HTTP 503/).to_stderr
  end

  # hall-of-fame-spec.md P4.1-2：沿用 LeapsIvCronGuard 的提早觸發防護。
  # 時間皆取自實際發生過的 pm2 觸發（P4 r2／P4.1-0）：11/07 00:27:40 提早、11/08 00:30:00 正點、11/09 00:45:20 延後。
  describe "pm2 cron 提早觸發防護（P4.1-2）" do
    let(:cron) { "30 0 * * *" }
    let(:ok)   { HallOfFame::HouseDailySync::Result.new(runs: {}, failures: []) }

    around do |example|
      original = ENV.fetch("cron_restart", nil)
      ENV["cron_restart"] = cron
      example.run
    ensure
      ENV["cron_restart"] = original
    end

    before { allow(service).to receive(:call).and_return(ok) }

    it "提早觸發（11/07 00:27:40 UTC）：略過，不呼叫 HouseDailySync、不寫 hof_sync_runs，印略過訊息" do
      runs_before = HallOfFame::SyncRun.count
      travel_to(Time.utc(2026, 11, 7, 0, 27, 40)) do
        expect { task.invoke }
          .to output(include("[hall_of_fame:sync_house] pm2 cron 提早觸發，略過：現在 2026-11-07T00:27:40Z，" \
                             "下一次排定 2026-11-07T00:30:00Z（cron 30 0 * * *，UTC）")).to_stdout
      end
      expect(HallOfFame::HouseDailySync).not_to have_received(:new)
      expect(HallOfFame::SyncRun.count).to eq(runs_before)
    end

    it "正點（11/08 00:30:00 UTC）：執行一次" do
      travel_to(Time.utc(2026, 11, 8, 0, 30, 0)) { task.invoke }

      expect(service).to have_received(:call).once
    end

    it "延後（11/09 00:45:20 UTC）：照常執行一次" do
      travel_to(Time.utc(2026, 11, 9, 0, 45, 20)) { task.invoke }

      expect(service).to have_received(:call).once
    end

    context "沒有 cron_restart（手動執行 bin/hall-of-fame-sync.sh）" do
      let(:cron) { nil }

      it "一律執行，即使時間落在提早區間" do
        travel_to(Time.utc(2026, 11, 7, 0, 27, 40)) { task.invoke }

        expect(service).to have_received(:call).once
      end
    end

    context "cron_restart 為不支援的寫法" do
      let(:cron) { "*/5 * * * *" }

      it "記 warn 後照常執行" do
        allow(Rails.logger).to receive(:warn)
        travel_to(Time.utc(2026, 11, 7, 0, 27, 40)) { task.invoke }

        expect(Rails.logger).to have_received(:warn).with(/無法判斷提早觸發，照常執行/)
        expect(service).to have_received(:call).once
      end
    end
  end
end
