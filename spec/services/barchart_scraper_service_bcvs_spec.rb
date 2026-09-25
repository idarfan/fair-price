# frozen_string_literal: true

require "rails_helper"

# bcvs 行為回歸（leaps-call-spread-spec 附錄 A 決議 1、2026-09-25）：
# bid/ask 篩選從快取寫入移到讀取後，bcvs 拿到的 chain 必須跟以前一樣，
# 不能多出 bid、ask 皆為 0 的列；到期日 sidecar 新增的兩個狀態也要對應回
# bcvs 原本的 no_candidates，/bcvs 畫面行為不變。
RSpec.describe BarchartScraperService, "bcvs" do
  subject(:service) { described_class.new("ORCL") }

  let(:expiration) { "2027-10-15-m" }
  let(:rows) do
    [
      { "strike" => 100, "bid" => 40.1, "ask" => 41.3, "last" => 40.5 },
      { "strike" => 230, "bid" => 0,    "ask" => 0,    "last" => 11.2 }
    ]
  end

  before do
    allow(service).to receive(:cdp_available?).and_return(true)
    allow(service).to receive(:log_fetch)
  end

  describe "#fetch_bcvs_call_chain" do
    it "returns only quotable rows right after a fresh scrape" do
      allow(service).to receive(:run_scraper).with("bcvs_call_chain", extra_args: [ expiration ])
        .and_return({ status: "success", data: { "rows" => rows, "underlying_price" => 139.54 } })

      result = service.fetch_bcvs_call_chain(expiration: expiration)

      expect(result[:status]).to eq("success")
      expect(result[:rows].map { |r| r["strike"] }).to eq([ 100 ])
    end

    it "returns only quotable rows when served from cache" do
      BcvsCacheService.upsert_chain!("ORCL", expiration, strikes: rows, underlying_price: 139.54)
      expect(service).not_to receive(:run_scraper)

      result = service.fetch_bcvs_call_chain(expiration: expiration)

      expect(result[:rows].map { |r| r["strike"] }).to eq([ 100 ])
    end
  end

  describe "#fetch_bcvs_expirations with the new sidecar statuses" do
    %w[symbol_not_found no_options].each do |sidecar_status|
      it "maps #{sidecar_status} to bcvs's existing no_candidates" do
        allow(service).to receive(:run_scraper).with("bcvs_expirations")
          .and_return({ status: sidecar_status, error: "scraper status=#{sidecar_status.inspect}" })

        expect(service.fetch_bcvs_expirations).to eq({ status: "no_candidates" })
      end
    end
  end
end
