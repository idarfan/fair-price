# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth gate", type: :request, skip_auto_auth: true do
  describe "unauthenticated" do
    it "redirects an existing page to /login" do
      get "/momentum"
      expect(response).to redirect_to(login_path)
    end

    it "leaves /up accessible" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end

    it "leaves /api/* accessible" do
      get "/api/v1/tracked_tickers"
      expect(response).to have_http_status(:ok)
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
