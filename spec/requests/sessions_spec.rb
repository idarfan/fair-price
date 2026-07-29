# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request, skip_auto_auth: true do
  def mock_google_auth(email:, uid: "google-uid-1")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
  end

  describe "GET /auth/google_oauth2/callback" do
    it "creates a pending user for a new email" do
      mock_google_auth(email: "newbie@example.com", uid: "uid-newbie")

      expect {
        get "/auth/google_oauth2/callback"
      }.to change(User, :count).by(1)

      user = User.find_by(google_uid: "uid-newbie")
      expect(user.status).to eq("pending")
      expect(user.admin).to be(false)
    end

    it "auto-enables and grants admin for ADMIN_EMAILS on first login" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ADMIN_EMAILS", "").and_return("mr.idarfan@gmail.com")

      mock_google_auth(email: "mr.idarfan@gmail.com", uid: "uid-admin")
      get "/auth/google_oauth2/callback"

      user = User.find_by(google_uid: "uid-admin")
      expect(user.status).to eq("enabled")
      expect(user.admin).to be(true)
      expect(user.approved_at).to be_present
    end

    it "reuses the existing record on a second login with the same google_uid" do
      existing = create(:user, google_uid: "uid-existing", email: "existing@example.com")
      mock_google_auth(email: "existing@example.com", uid: "uid-existing")

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change(User, :count)

      expect(session[:user_id]).to eq(existing.id)
    end

    it "redirects disabled users to /account_disabled" do
      create(:user, google_uid: "uid-disabled", email: "disabled@example.com", status: :disabled)
      mock_google_auth(email: "disabled@example.com", uid: "uid-disabled")

      get "/auth/google_oauth2/callback"

      expect(response).to redirect_to(account_disabled_path)
    end

    it "redirects new users (totp not enabled) to /two_factor/setup" do
      mock_google_auth(email: "no-totp@example.com", uid: "uid-no-totp")

      get "/auth/google_oauth2/callback"

      expect(response).to redirect_to("/two_factor/setup")
    end
  end

  describe "DELETE /logout" do
    it "clears the session and redirects to /login" do
      user = create(:user)
      mock_google_auth(email: user.email, uid: user.google_uid)
      get "/auth/google_oauth2/callback"
      expect(session[:user_id]).to eq(user.id)

      delete "/logout"

      expect(response).to redirect_to(login_path)
      expect(session[:user_id]).to be_nil
    end
  end
end
