# frozen_string_literal: true

require "rails_helper"

# 價格情境兩支爬蟲（volap／price_history）加外層逾時。爬蟲內部各自有等待上限，
# 但 CDP 連線本身沒回應時 Open3.capture3 會無限等下去，job 不結束、排程鎖也不會解。
# 其他爬蟲（LEAPS 本來就要 3–5 分鐘）不套，行為不變。
RSpec.describe BarchartScraperService, "#run_scraper" do
  subject(:service) { described_class.new("TSTX") }

  let(:timed_out) { TimedCapture::Result.new(stdout: "", stderr: "", status: nil, timed_out: true) }

  def ok_result(json)
    TimedCapture::Result.new(stdout: json, stderr: "",
                             status: instance_double(Process::Status, success?: true),
                             timed_out: false)
  end

  %w[volap price_history].each do |type|
    it "#{type}：帶 SCRAPER_TIMEOUTS_S 的時限執行" do
      expect(TimedCapture).to receive(:call)
        .with("python3", end_with("#{type}_scraper.py"), "TSTX",
              timeout: described_class::SCRAPER_TIMEOUTS_S.fetch(type), chdir: Rails.root.to_s)
        .and_return(ok_result('{"status":"success"}'))

      expect(service.send(:run_scraper, type)[:status]).to eq("success")
    end

    it "#{type}：逾時回 scraper_timeout，而不是一直等" do
      allow(TimedCapture).to receive(:call).and_return(timed_out)

      result = service.send(:run_scraper, type)

      expect(result[:status]).to eq("scraper_timeout")
      expect(result[:error]).to include(described_class::SCRAPER_TIMEOUTS_S.fetch(type).to_s)
    end
  end

  it "時限比爬蟲內部的等待上限長，正常路徑不會被誤砍" do
    expect(described_class::SCRAPER_TIMEOUTS_S.fetch("volap")).to be >= 8 + 45 + 60 + 30
    expect(described_class::SCRAPER_TIMEOUTS_S.fetch("price_history")).to be >= 45 + 30
  end

  it "其他爬蟲不套時限，照舊用 Open3.capture3" do
    expect(TimedCapture).not_to receive(:call)
    expect(Open3).to receive(:capture3)
      .and_return([ '{"status":"success"}', "", instance_double(Process::Status, success?: true) ])

    service.send(:run_scraper, "leaps")
  end

  it "fetch_volap 逾時：狀態原樣往上傳，FetchLog 也真的寫得進去" do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(TimedCapture).to receive(:call).and_return(timed_out)

    expect { expect(service.fetch_volap[:status]).to eq("scraper_timeout") }
      .to change { FetchLog.where(symbol: "TSTX", status: "scraper_timeout").count }.by(1)
  end

  it "scraper_timeout 有登記在 FetchLog::STATUSES" do
    expect(FetchLog::STATUSES).to include("scraper_timeout")
  end
end
