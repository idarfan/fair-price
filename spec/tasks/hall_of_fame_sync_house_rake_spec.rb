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
end
