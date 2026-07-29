# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TwoFactor", type: :request, skip_auto_auth: true do
  let(:user) { create(:user, status: :enabled) }

  describe "GET /two_factor/setup" do
    it "redirects to /login when not signed in" do
      get "/two_factor/setup"
      expect(response).to redirect_to(login_path)
    end

    it "renders the setup page and stores a pending secret in session" do
      sign_in_as(user)
      get "/two_factor/setup"

      expect(response).to have_http_status(:ok)
      expect(session[:pending_totp_secret]).to be_present
    end
  end

  describe "POST /two_factor/setup" do
    it "does not enable totp with a wrong code" do
      sign_in_as(user)
      get "/two_factor/setup"

      post "/two_factor/setup", params: { code: "000000" }

      expect(user.reload.totp_enabled).to be(false)
    end

    it "enables totp, generates backup codes, and redirects with a correct code" do
      sign_in_as(user)
      get "/two_factor/setup"
      secret = session[:pending_totp_secret]
      code   = ROTP::TOTP.new(secret).now

      post "/two_factor/setup", params: { code: code }

      expect(response).to redirect_to("/two_factor/backup_codes")
      expect(user.reload.totp_enabled).to be(true)
      expect(user.totp_secret).to eq(secret)
      expect(JSON.parse(user.backup_codes).size).to eq(10)
      expect(session[:backup_codes_plaintext].size).to eq(10)
    end
  end

  describe "GET /two_factor/backup_codes" do
    it "shows codes once then nil on a second visit" do
      sign_in_as(user)
      get "/two_factor/setup"
      code = ROTP::TOTP.new(session[:pending_totp_secret]).now
      post "/two_factor/setup", params: { code: code }

      get "/two_factor/backup_codes"
      expect(response.body).to be_present
      expect(session[:backup_codes_plaintext]).to be_nil
    end
  end

  describe "POST /two_factor/challenge" do
    before do
      user.update!(totp_secret: "base32secret3232", totp_enabled: true)
      sign_in_as(user)
    end

    it "verifies a correct TOTP code" do
      code = ROTP::TOTP.new("base32secret3232").now
      post "/two_factor/challenge", params: { code: code }

      expect(session[:totp_verified]).to be(true)
    end

    it "accepts an unused backup code exactly once" do
      codes = user.generate_backup_codes!

      post "/two_factor/challenge", params: { code: codes.first }
      expect(session[:totp_verified]).to be(true)

      expect(user.reload.consume_backup_code!(codes.first)).to be(false)
    end

    it "locks out after 5 wrong attempts" do
      5.times do
        post "/two_factor/challenge", params: { code: "000000" }
      end
      expect(session[:totp_locked_until]).to be_present

      code = ROTP::TOTP.new("base32secret3232").now
      post "/two_factor/challenge", params: { code: code }
      expect(session[:totp_verified]).to be(false)
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
