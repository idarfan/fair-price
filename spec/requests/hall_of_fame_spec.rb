# frozen_string_literal: true

require "rails_helper"

RSpec.describe "投資名人堂", type: :request do
  let!(:pelosi) { create(:hof_official, slug: "pelosi", display_name: "Nancy Pelosi", last_name: "Pelosi", first_name: "Nancy") }

  describe "GET /hall_of_fame" do
    it "renders the congress tab with Pelosi in the mount data" do
      get "/hall_of_fame"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("投資名人堂", "國會議員", "Nancy Pelosi", 'id="hall-of-fame-root"', 'data-tab="congress"')
    end

    it "renders the executive tab" do
      get "/hall_of_fame", params: { tab: "executive" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("行政政要", 'data-tab="executive"')
    end

    it "falls back to the congress tab for an unknown tab" do
      get "/hall_of_fame", params: { tab: "<script>" }

      expect(response.body).to include('data-tab="congress"')
    end
  end

  describe "sidebar 入口" do
    it "是最末位，href 可被路由解析" do
      entry = FairValue::AppSwitcherComponent::APP_LINKS.last

      expect(entry).to include(label: "投資名人堂", href: "/hall_of_fame")
      expect(Rails.application.routes.recognize_path(entry[:href])).to eq(controller: "hall_of_fame", action: "index")
    end
  end

  describe "GET /api/v1/hall_of_fame/officials" do
    it "returns the cards for a category" do
      get "/api/v1/hall_of_fame/officials", params: { category: "congress" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["officials"].map { |o| o["display_name"] }).to eq([ "Nancy Pelosi" ])
    end

    it "rejects an unknown category" do
      get "/api/v1/hall_of_fame/officials", params: { category: "senate" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/hall_of_fame/officials/:slug" do
    it "returns holdings, trades and update times through the service" do
      annual = create(:hof_filing, official: pelosi, filing_type: "annual", year: 2025, parse_status: "parsed")
      create(:hof_holding, filing: annual, value_min: 1_000, value_max: 3_000)
      ptr = create(:hof_filing, official: pelosi, parse_status: "parsed", filing_date: Time.zone.today)
      create(:hof_trade, filing: ptr, tx_date: Time.zone.today)

      get "/api/v1/hall_of_fame/officials/pelosi"

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body.dig("holdings", "as_of")).to eq("2025/12/31")
      expect(body.dig("holdings", "views", "all", "rows", 0, "estimated")).to eq(100.0)
      expect(body.dig("trades", "rows").size).to eq(1)
      expect(body["synced_at"].keys).to eq(%w[index pdf_parse options])
    end

    it "returns 404 for an unknown slug" do
      get "/api/v1/hall_of_fame/officials/nobody"

      expect(response).to have_http_status(:not_found)
    end
  end
end
