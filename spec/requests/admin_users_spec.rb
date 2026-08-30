# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", :skip_auto_auth, type: :request do
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

    it "shows a per-day breakdown of the last 7 days alongside the accumulated total" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      create(:user_activity, user: target, kind: :page_view, duration_ms: 60_000,
                              started_at: Time.zone.local(2026, 8, 17, 10, 0, 0))
      create(:user_activity, user: target, kind: :page_view, duration_ms: 90_000,
                              started_at: Time.zone.local(2026, 8, 18, 9, 0, 0))
      # 8 天前的舊資料不該算進「近7天每日拆分」，但仍計入總使用時數
      create(:user_activity, user: target, kind: :page_view, duration_ms: 999_000,
                              started_at: 8.days.ago)

      travel_to Time.zone.local(2026, 8, 18, 12, 0, 0) do
        sign_in_and_verify_totp!(admin)
        get "/admin/users"
      end

      body = response.body
      expect(body).to include("08/18")
      expect(body).to include("1分30秒") # 8/18 當日 90_000ms
      expect(body).to include("08/17")
      expect(body).to include("1分0秒") # 8/17 當日 60_000ms
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

    it "groups the browsing trail into separate date sections with month/day/weekday headers, newest first" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      yesterday = Time.zone.local(2026, 8, 5, 10, 0, 0)
      today     = Time.zone.local(2026, 8, 6, 9, 0, 0)
      create(:user_activity, user: target, kind: :page_view, path: "/momentum", started_at: yesterday)
      create(:user_activity, user: target, kind: :page_view, path: "/leaps", started_at: today)

      sign_in_and_verify_totp!(admin)
      get "/admin/users/#{target.id}"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("2026年08月05日（三）")
      expect(body).to include("2026年08月06日（四）")
      # 最近日期排最前面
      day1_idx = body.index("2026年08月06日")
      day2_idx = body.index("2026年08月05日")
      expect(day1_idx).to be < day2_idx
      # 跨日不推導下一步——8/5 那筆的「下一步去哪」不能指向 8/6 的 /leaps，
      # 應該顯示「當日結束瀏覽」
      expect(body[day2_idx..]).to include("當日結束瀏覽")
    end

    it "expands only the most recent date's <details> section by default" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      create(:user_activity, user: target, kind: :page_view, path: "/momentum",
                              started_at: Time.zone.local(2026, 8, 5, 10, 0, 0))
      create(:user_activity, user: target, kind: :page_view, path: "/leaps",
                              started_at: Time.zone.local(2026, 8, 6, 9, 0, 0))

      sign_in_and_verify_totp!(admin)
      get "/admin/users/#{target.id}"

      body = response.body
      day1_idx = body.index("<details")
      day2_idx = body.index("<details", day1_idx + 1)
      expect(body[day1_idx...day1_idx + 40]).to include("open")
      expect(body[day2_idx...day2_idx + 40]).not_to include("open")
    end

    it "shows each date group's total dwell time next to the count" do
      admin  = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: true)
      target = create(:user, status: :enabled)
      create(:user_activity, user: target, kind: :page_view, path: "/momentum",
                              duration_ms: 60_000, started_at: Time.zone.local(2026, 8, 6, 9, 0, 0))
      create(:user_activity, user: target, kind: :page_view, path: "/leaps",
                              duration_ms: 30_000, started_at: Time.zone.local(2026, 8, 6, 10, 0, 0))

      sign_in_and_verify_totp!(admin)
      get "/admin/users/#{target.id}"

      expect(response.body).to include("合計停留 1分30秒")
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
