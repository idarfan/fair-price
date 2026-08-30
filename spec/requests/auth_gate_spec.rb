# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth gate", :skip_auto_auth, type: :request do
  describe "unauthenticated" do
    it "redirects an existing page to /login" do
      get "/momentum"
      expect(response).to redirect_to(login_path)
    end

    it "leaves /up accessible" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end

    # 2026-08-28 安全修正：/api/* 過去被列在 GATE_EXEMPT_PREFIXES，導致整個 API
    # 命名空間在公網（fairprice-ohmy.com）上可匿名讀取與刪除。現在 API 與 UI
    # 共用同一份閘門，只是把 302 導頁換成 401 JSON。
    it "rejects /api/* with 401 JSON instead of redirecting" do
      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
    end

    it "leaves /track accessible (自行檢查 logged_in?，未登入回 204)" do
      post "/track/page_view", params: { activity_token: SecureRandom.uuid, path: "/" }
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "logged in, totp not enabled" do
    it "redirects to /two_factor/setup" do
      user = create(:user, status: :enabled, totp_enabled: false)
      sign_in_as(user)

      get "/momentum"
      expect(response).to redirect_to("/two_factor/setup")
    end
  end

  describe "logged in, totp enabled but not verified this session" do
    it "redirects to /two_factor/challenge" do
      user = create(:user, status: :enabled, totp_enabled: true, totp_secret: "base32secret3232")
      sign_in_as(user)

      get "/momentum"
      expect(response).to redirect_to("/two_factor/challenge")
    end
  end

  describe "fully verified but pending approval" do
    it "redirects to /pending_approval" do
      user = create(:user, status: :pending, totp_enabled: true, totp_secret: "base32secret3232")
      sign_in_as(user)
      code = ROTP::TOTP.new("base32secret3232").now
      post "/two_factor/challenge", params: { code: code }

      get "/momentum"
      expect(response).to redirect_to("/pending_approval")
    end
  end

  describe "fully verified and enabled" do
    it "passes through to the page" do
      user = create(:user, status: :enabled, totp_enabled: true, totp_secret: "base32secret3232")
      sign_in_as(user)
      code = ROTP::TOTP.new("base32secret3232").now
      post "/two_factor/challenge", params: { code: code }

      get "/momentum"
      expect(response).to have_http_status(:ok)
    end
  end
end
