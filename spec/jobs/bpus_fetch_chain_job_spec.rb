# frozen_string_literal: true

require "rails_helper"

RSpec.describe BpusFetchChainJob, type: :job do
  let(:symbol)     { "RKLB" }
  let(:expiration) { "2026-08-21-m" }
  let(:job_id)     { "abc123def456" }

  describe "#perform — rescue path (exception from service)" do
    before do
      allow(BarchartScraperService).to receive(:new).and_raise(RuntimeError, "connection reset by peer")
    end

    it "writes error status to job cache" do
      expect(Rails.cache).to receive(:write).with(
        "bpus_job_#{job_id}",
        { status: "error", errors: [ "connection reset by peer" ] },
        expires_in: 5.minutes
      )
      described_class.perform_now(symbol, expiration, job_id)
    end
  end

  describe "#perform — success path" do
    before do
      svc = instance_double(BarchartScraperService)
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
      allow(svc).to receive(:fetch_bpus_put_chain).with(expiration: expiration)
        .and_return({ status: "success", errors: [] })
    end

    it "writes success status to job cache, calling the service with the correct expiration kwarg" do
      expect(Rails.cache).to receive(:write).with(
        "bpus_job_#{job_id}",
        { status: "success", errors: [] },
        expires_in: 5.minutes
      )
      described_class.perform_now(symbol, expiration, job_id)
    end
  end

  describe "#perform — barchart_session_expired path" do
    before do
      svc = instance_double(BarchartScraperService, fetch_bpus_put_chain: { status: "barchart_session_expired" })
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "maps to session_expired status" do
      expect(Rails.cache).to receive(:write).with(
        "bpus_job_#{job_id}",
        { status: "session_expired", errors: [] },
        expires_in: 5.minutes
      )
      described_class.perform_now(symbol, expiration, job_id)
    end
  end

  describe "#perform — no_candidates path" do
    before do
      svc = instance_double(BarchartScraperService, fetch_bpus_put_chain: { status: "no_candidates" })
      allow(BarchartScraperService).to receive(:new).with(symbol).and_return(svc)
    end

    it "maps to no_candidates status" do
      expect(Rails.cache).to receive(:write).with(
        "bpus_job_#{job_id}",
        { status: "no_candidates", errors: [] },
        expires_in: 5.minutes
      )
      described_class.perform_now(symbol, expiration, job_id)
    end
  end
end
