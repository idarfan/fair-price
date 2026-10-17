# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "hall_of_fame:retry_failed_house_pdfs", type: :task do
  let(:task)   { Rake::Task["hall_of_fame:retry_failed_house_pdfs"] }
  let(:parser) { instance_double(HallOfFame::HousePdfParse) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("hall_of_fame:retry_failed_house_pdfs")
    task.reenable
    Rake::Task["hall_of_fame:parse_house_pdfs"].reenable
    allow(HallOfFame::HousePdfParse).to receive(:new).and_return(parser)
  end

  it "resets only failed house filings to pending, then runs the parser" do
    failed   = create(:hof_filing, parse_status: "failed", parse_error: "sidecar 結束碼 1")
    review   = create(:hof_filing, parse_status: "needs_review", parse_error: "掃描檔")
    statuses = nil
    allow(parser).to receive(:call) do
      statuses = HallOfFame::Filing.order(:id).pluck(:parse_status, :parse_error)
      HallOfFame::HousePdfParse::Summary.new(counts: { "parsed" => 1 }, errors: [])
    end

    expect { task.invoke }.to output(/改回 pending 1 筆.*parsed 1/m).to_stdout

    expect(statuses).to eq([ [ "pending", nil ], [ "needs_review", "掃描檔" ] ])
    expect(failed.reload.parse_status).to eq("pending")
    expect(review.reload.parse_status).to eq("needs_review")
  end
end
