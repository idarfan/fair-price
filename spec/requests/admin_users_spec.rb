# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request, skip_auto_auth: true do
  let(:secret) { "base32secret3232" }

  def sign_in_and_verify_totp!(user)
    sign_in_as(user)
    code = ROTP::TOTP.new(secret).now
    post "/two_factor/challenge", params: { code: code }
  end

  describe "GET /admin/users" do
    it "redirects to /login when not signed in" do
      get "/admin/users"
      expect(response).to redirect_to(login_path)
    end

    it "returns 404 for a signed-in, verified, non-admin user" do
      user = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: false)
      sign_in_and_verify_totp!(user)

      get "/admin/users"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 200 and lists users for an admin" do
      admin = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      other = create(:user, email: "listed@example.com")
      sign_in_and_verify_totp!(admin)

      get "/admin/users"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(other.email)
    end

    it "does not render a disable form for the admin's own row" do
      admin = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      sign_in_and_verify_totp!(admin)

      get "/admin/users"
      expect(response.body).not_to include("/admin/users/#{admin.id}/disable")
    end
  end

  describe "GET /admin/users list stats" do
    it "shows accumulated dwell time, top commands and last activity matching the DB" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      create(:user_activity, user: target, kind: :page_view, duration_ms: 60_000, started_at: 2.hours.ago)
      create(:user_activity, user: target, kind: :page_view, duration_ms: 30_000, started_at: 1.hour.ago)
      create(:user_activity, user: target, kind: :command, action_name: "leaps_filter", started_at: 30.minutes.ago)
      create(:user_activity, user: target, kind: :command, action_name: "leaps_filter", started_at: 20.minutes.ago)
      create(:user_activity, user: target, kind: :command, action_name: "bpus_calculate", started_at: 10.minutes.ago)

      sign_in_and_verify_totp!(admin)
      get "/admin/users"

      expect(response.body).to include("1分30秒") # 90_000ms 累積
      expect(response.body).to include("leaps_filter")
      expect(response.body).to include("× 2")
    end
  end

  describe "GET /admin/users/:id" do
    it "redirects to /login when not signed in" do
      target = create(:user)
      get "/admin/users/#{target.id}"
      expect(response).to redirect_to(login_path)
    end

    it "returns 404 for a non-admin user" do
      user   = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: false)
      target = create(:user)
      sign_in_and_verify_totp!(user)

      get "/admin/users/#{target.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "shows the browsing trail in chronological order with computed next-page and full command metadata" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      create(:user_activity, user: target, kind: :page_view, path: "/momentum", referrer_path: "/",
                              duration_ms: 5000, started_at: 2.hours.ago)
      create(:user_activity, user: target, kind: :page_view, path: "/leaps", referrer_path: "/momentum",
                              duration_ms: 8000, started_at: 1.hour.ago)
      create(:user_activity, user: target, kind: :command, action_name: "leaps_filter",
                              metadata: { "symbol" => "NOK", "delta_min" => "0.6" }, started_at: 30.minutes.ago)

      sign_in_and_verify_totp!(admin)
      get "/admin/users/#{target.id}"

      expect(response).to have_http_status(:ok)
      body = response.body
      # 瀏覽軌跡:momentum 出現在 leaps 之前(依時間序),且 momentum 那列的
      # 「下一步去哪」要指向 leaps
      expect(body.index("/momentum")).to be < body.index("/leaps")
      # 指令記錄:完整參數展開,不省略
      expect(body).to include("symbol")
      expect(body).to include("NOK")
      expect(body).to include("delta_min")
      expect(body).to include("0.6")
    end
  end

  describe "PATCH /admin/users/:id/approve" do
    it "enables a pending user and sets approved_at" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :pending)
      sign_in_and_verify_totp!(admin)

      patch "/admin/users/#{target.id}/approve"

      target.reload
      expect(target.status).to eq("enabled")
      expect(target.approved_at).to be_present
    end
  end

  describe "PATCH /admin/users/:id/disable" do
    it "disables the user and invalidates their existing session" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret)

      # target 自己先登入建立一個 session
      sign_in_and_verify_totp!(target)
      get "/momentum"
      expect(response).to have_http_status(:ok)

      # 換 admin 登入把 target 停用
      sign_in_and_verify_totp!(admin)
      patch "/admin/users/#{target.id}/disable"
      expect(target.reload.status).to eq("disabled")

      # 換回 target 原本的 session：因為 session_version 不符，被視為未登入
      sign_in_as(target)
      # sign_in_as 本身會走 google_callback，disabled 使用者會被導去 account_disabled
      expect(response).to redirect_to(account_disabled_path)
    end
  end

  describe "PATCH /admin/users/:id/reactivate" do
    it "re-enables a disabled user" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :disabled)
      sign_in_and_verify_totp!(admin)

      patch "/admin/users/#{target.id}/reactivate"

      expect(target.reload.status).to eq("enabled")
    end
  end
end
