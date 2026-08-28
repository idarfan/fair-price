# frozen_string_literal: true

require "rails_helper"

# 迴歸測試：2026-08-28 之前 GATE_EXEMPT_PREFIXES 含 "/api"，整個 API 命名空間
# 在公網上可匿名讀取與刪除。這支測試把「API 必須認證」釘住。
RSpec.describe "API auth gate", type: :request, skip_auto_auth: true do
  describe "未登入" do
    it "讀取端點回 401 JSON，而不是 302 導頁" do
      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include("error" => "unauthenticated")
    end

    it "/api/iv_analysis 命名空間同樣受保護" do
      get "/api/iv_analysis/watchlist"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include("error" => "unauthenticated")
    end

    it "破壞性端點擋在資料被刪除之前" do
      ticker = create(:tracked_ticker)

      expect {
        delete "/api/v1/tracked_tickers/#{ticker.id}"
      }.not_to change(TrackedTicker, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "不會外洩任何資料內容" do
      create(:tracked_ticker, symbol: "SECRET")

      get "/api/v1/tracked_tickers"

      expect(response.body).not_to include("SECRET")
    end
  end

  describe "已登入但未通過 2FA" do
    it "回 403 而不是導向 /two_factor/setup" do
      user = create(:user, status: :enabled, totp_enabled: false)
      sign_in_as(user)

      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("error" => "totp_setup_required")
    end
  end

  describe "帳號已停用" do
    it "回 403 account_disabled" do
      user = create(:user, status: :enabled, totp_enabled: true, totp_secret: AuthHelpers::DEFAULT_TOTP_SECRET)
      sign_in_and_pass_totp!(user: user)
      user.update!(status: :disabled)

      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("error" => "account_disabled")
    end
  end

  describe "完整通過閘門" do
    it "正常回傳資料" do
      sign_in_and_pass_totp!
      create(:tracked_ticker, symbol: "AAPL")

      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |t| t["symbol"] }).to include("AAPL")
    end
  end
end
