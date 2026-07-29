# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AccountSecurity", type: :request, skip_auto_auth: true do
  let(:secret) { "base32secret3232" }
  let(:user) { create(:user, status: :enabled, totp_enabled: true, totp_secret: secret) }

  def sign_in_and_verify_totp!
    sign_in_as(user)
    code = ROTP::TOTP.new(secret).now
    post "/two_factor/challenge", params: { code: code }
  end

  describe "GET /settings/security" do
    it "redirects to /login when not signed in" do
      get "/settings/security"
      expect(response).to redirect_to(login_path)
    end

    it "renders for a fully verified user" do
      sign_in_and_verify_totp!
      get "/settings/security"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /settings/security/backup_codes" do
    it "invalidates old codes and issues a fresh set" do
      sign_in_and_verify_totp!
      old_codes = user.generate_backup_codes!

      post "/settings/security/backup_codes"

      expect(response).to redirect_to("/two_factor/backup_codes")
      expect(session[:backup_codes_plaintext].size).to eq(10)
      expect(user.reload.consume_backup_code!(old_codes.first)).to be(false)
    end
  end

  describe "POST /settings/security/logout_all" do
    it "bumps session_version and signs the current session out too" do
      sign_in_and_verify_totp!
      expect { post "/settings/security/logout_all" }.to change { user.reload.session_version }.by(1)

      expect(response).to redirect_to(login_path)
      get "/momentum"
      expect(response).to redirect_to(login_path)
    end

    it "invalidates other sessions holding the old session_version" do
      sign_in_and_verify_totp!

      # 模擬在另一台裝置的帳戶安全頁按下「登出所有裝置」
      user.bump_session_version!

      get "/momentum"
      expect(response).to redirect_to(login_path)
    end
  end
end
