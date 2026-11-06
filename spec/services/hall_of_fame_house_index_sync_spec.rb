# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::HouseIndexSync do
  let(:zip_bytes) { file_fixture("hall_of_fame/2026FD.zip").binread }
  let(:zip_url)   { described_class.zip_url(2026) }
  let(:etag)      { '"41da7d18a55cdd1:0"' }
  let(:last_mod)  { "Fri, 16 Oct 2026 10:00:00 GMT" }
  let!(:pelosi)   { create(:hof_official, slug: "pelosi", last_name: "Pelosi", first_name: "Nancy", district: "CA11") }
  let!(:khanna)   { create(:hof_official, slug: "khanna", last_name: "Khanna", first_name: "Ro", district: "CA17") }

  def stub_zip_ok
    WebMock.stub_request(:get, zip_url)
           .to_return(status: 200, body: zip_bytes, headers: { "ETag" => etag, "Last-Modified" => last_mod })
  end

  def sync = described_class.new(years: [ 2026 ]).call

  describe "first run" do
    before { stub_zip_ok }

    it "inserts only listed officials with mappable filing types" do
      run = sync

      expect(run.new_filings_count).to eq(4)
      expect(HallOfFame::Filing.order(:doc_id).pluck(:doc_id, :filing_type)).to eq(
        [ %w[10070001 annual], %w[10070002 amendment], %w[20033725 ptr], %w[8221322 ptr] ]
      )
    end

    it "matches by exact Last and First prefix (Ro → Rohit) and ignores other Khannas" do
      sync
      expect(HallOfFame::Filing.where(official: khanna).pluck(:doc_id)).to eq([ "8221322" ])
      expect(HallOfFame::Filing.where(doc_id: %w[8084 20039999])).to be_empty
    end

    it "builds pdf urls by filing type and parses the filing date" do
      sync
      ptr    = HallOfFame::Filing.find_by!(doc_id: "20033725")
      annual = HallOfFame::Filing.find_by!(doc_id: "10070001")

      expect(ptr.pdf_url).to eq("https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2026/20033725.pdf")
      expect(annual.pdf_url).to eq("https://disclosures-clerk.house.gov/public_disc/financial-pdfs/2026/10070001.pdf")
      expect(ptr).to have_attributes(source: "house", year: 2026, filing_date: Date.new(2026, 1, 16),
                                     parse_status: "pending", official_id: pelosi.id)
    end

    it "keeps a StateDst mismatch as a warning without dropping the filing" do
      run = sync
      expect(run.error_count).to eq(0)
      expect(run.error_log).to include("[警示] khanna DocID 8221322 StateDst=CA18，名單為 CA17")
      expect(run.error_log).to include("[略過] pelosi DocID 10070003 FilingType=C")
    end

    it "stores the validators of the downloaded ZIP" do
      run = sync
      expect(run.http_validators).to eq(zip_url => { "etag" => etag, "last_modified" => last_mod })
      expect(run.finished_at).to be_present
    end
  end

  describe "re-run" do
    it "sends conditional headers and stops on 304" do
      stub_zip_ok
      sync
      not_modified = WebMock.stub_request(:get, zip_url)
                            .with(headers: { "If-None-Match" => etag, "If-Modified-Since" => last_mod })
                            .to_return(status: 304)

      run = sync

      expect(not_modified).to have_been_requested
      expect(run.new_filings_count).to eq(0)
      expect(run.http_validators).to eq(zip_url => { "etag" => etag, "last_modified" => last_mod })
      expect(HallOfFame::Filing.count).to eq(4)
    end

    it "is idempotent when the server ignores validators and returns 200 again" do
      stub_zip_ok
      sync
      run = sync

      expect(run.new_filings_count).to eq(0)
      expect(HallOfFame::Filing.count).to eq(4)
    end

    it "does not overwrite an existing filing" do
      stub_zip_ok
      sync
      HallOfFame::Filing.find_by!(doc_id: "20033725").update!(parse_status: "parsed")
      sync

      expect(HallOfFame::Filing.find_by!(doc_id: "20033725").parse_status).to eq("parsed")
    end
  end

  describe "failures" do
    it "records an HTTP error, keeps previous validators and still finishes the run" do
      stub_zip_ok
      sync
      WebMock.stub_request(:get, zip_url).to_return(status: 503)

      run = sync

      expect(run.error_count).to eq(1)
      expect(run.error_log).to include("HTTP 503")
      expect(run.http_validators).to eq(zip_url => { "etag" => etag, "last_modified" => last_mod })
      expect(run.finished_at).to be_present
    end

    it "records a corrupt ZIP as an error without writing filings" do
      WebMock.stub_request(:get, zip_url).to_return(status: 200, body: "not a zip")

      run = sync

      expect(run.error_count).to eq(1)
      expect(run.error_log).to include("解壓 2026FD.xml 失敗")
      expect(run.http_validators).to eq({})
      expect(HallOfFame::Filing.count).to eq(0)
    end

    it "records a network timeout as an error" do
      WebMock.stub_request(:get, zip_url).to_timeout

      run = sync

      expect(run.error_count).to eq(1)
      expect(run.error_log).to include("下載失敗")
    end

    it "continues with the other year when one year fails" do
      stub_zip_ok
      WebMock.stub_request(:get, described_class.zip_url(2025)).to_return(status: 404)

      run = described_class.new(years: [ 2026, 2025 ]).call

      expect(run.new_filings_count).to eq(4)
      expect(run.error_count).to eq(1)
      expect(run.error_log).to include("2025：", "HTTP 404")
    end
  end

  it "defaults to the current and previous year" do
    travel_to Time.zone.local(2026, 10, 17, 9) do
      WebMock.stub_request(:get, described_class.zip_url(2026)).to_return(status: 304)
      WebMock.stub_request(:get, described_class.zip_url(2025)).to_return(status: 304)

      run = described_class.new.call

      expect(run.error_count).to eq(0)
      expect(WebMock).to have_requested(:get, described_class.zip_url(2025))
    end
  end
end
