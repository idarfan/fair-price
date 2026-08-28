# frozen_string_literal: true

# JSON API 版本的登入閘門。
#
# API 與 UI 共用 ApplicationController#enforce_auth_gate 的判斷邏輯（同一份 session、
# 同一套 2FA 與逾時規則），這個 concern 只負責換掉「被拒絕時怎麼回應」：
# HTML 導頁 302 對 fetch() 客戶端沒有意義，改成語意正確的 401 / 403 JSON。
module JsonAuthGate
  extend ActiveSupport::Concern

  # 未登入與逾時都是「請重新取得憑證」→ 401
  # 已登入但條件不足（停用、未過 2FA、待核准）→ 403
  DENY_STATUSES = {
    unauthenticated:            :unauthorized,
    idle_timeout:               :unauthorized,
    absolute_timeout:           :unauthorized,
    account_disabled:           :forbidden,
    totp_setup_required:        :forbidden,
    totp_verification_required: :forbidden,
    pending_approval:           :forbidden
  }.freeze

  DENY_MESSAGES = {
    unauthenticated:            "請先登入",
    idle_timeout:               "閒置超過 2 小時，請重新登入",
    absolute_timeout:           "登入已滿 24 小時，請重新登入",
    account_disabled:           "此帳號已停用",
    totp_setup_required:        "請先完成雙因子驗證設定",
    totp_verification_required: "請先通過雙因子驗證",
    pending_approval:           "帳號尚未核准"
  }.freeze

  included do
    protect_from_forgery with: :exception

    rescue_from ActionController::InvalidAuthenticityToken do
      render json: { error: "invalid_authenticity_token", message: "請重新整理頁面後再試" },
             status: :unprocessable_entity
    end
  end

  private

  def gate_deny(reason, alert: nil)
    render json: {
      error:   reason.to_s,
      message: alert || DENY_MESSAGES.fetch(reason, "無法存取")
    }, status: DENY_STATUSES.fetch(reason, :unauthorized)
  end
end
