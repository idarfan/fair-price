# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScrapeLeapsJob, type: :job do
  let(:symbol) { "NOK" }
  let(:job_id) { "abc123def456" }

  describe "#perform — rescue path (exception from service)" do
    before do
      allow(BarchartScraperService).to receive(:new).and_raise(RuntimeError, "connection reset by peer")
    end

    it "writes error status to job cache" do
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "error", errors: [ "connection reset by peer" ] },
        expires_in: 30.minutes
      )
      allow(Rails.cache).to receive(:write)  # allow leaps_last_errors_ write
      described_class.perform_now(symbol, job_id)
    end

    it "writes error message to leaps_last_errors_{symbol} cache" do
      allow(Rails.cache).to receive(:write)  # allow job cache write
      expect(Rails.cache).to receive(:write).with(
        "leaps_last_errors_#{symbol}",
        [ "connection reset by peer" ],
        expires_in: 30.minutes
      )
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — success path" do
    let(:fake_result) { { status: "success", errors: [] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result)
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes success status to job cache" do
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "success", errors: [] },
        expires_in: 30.minutes
      )
      described_class.perform_now(symbol, job_id)
    end

    it "does not write leaps_last_errors when errors is empty" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).not_to receive(:write).with("leaps_last_errors_#{symbol}", anything, anything)
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — partial_error path" do
    let(:partial_msg) { "Session 在抓取 2027-01-17 的 Options Prices 時過期，已抓到的部分可能不完整，請重新查詢" }
    let(:fake_result) { { status: "partial_error", errors: [ partial_msg ] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result)
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes partial_error status to job cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "partial_error", errors: [ partial_msg ] },
        expires_in: 30.minutes
      )
      described_class.perform_now(symbol, job_id)
    end

    it "writes error message to leaps_last_errors_{symbol} cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_last_errors_#{symbol}",
        [ partial_msg ],
        expires_in: 30.minutes
      )
      described_class.perform_now(symbol, job_id)
    end
  end

  describe "#perform — session_expired path" do
    let(:fake_result) { { status: "barchart_session_expired", errors: [] } }

    before do
      svc = instance_double(BarchartScraperService, fetch_leaps: fake_result)
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "writes session_expired status to job cache" do
      allow(Rails.cache).to receive(:write)
      expect(Rails.cache).to receive(:write).with(
        "leaps_job_#{job_id}",
        { status: "session_expired", errors: [] },
        expires_in: 30.minutes
      )
      described_class.perform_now(symbol, job_id)
    end
  end
end
