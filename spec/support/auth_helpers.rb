module AuthHelpers
  DEFAULT_TOTP_SECRET = "jbswy3dpehpk3pxp"

  def sign_in_as(user)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: user.google_uid,
      info: { email: user.email }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    get "/auth/google_oauth2/callback"
  end

  # 讓一個使用者完整通過全域 auth gate（登入 + TOTP 設定 + TOTP 驗證），
  # 給那些跟認證流程本身無關、只是需要「已登入」才能測試自身邏輯的
  # request spec 用。走真的 sign_in_as + 真的 /two_factor/challenge，
  # 不直接改 session，避免跟真實流程行為分歧。
  def sign_in_and_pass_totp!(user: nil)
    user ||= FactoryBot.create(:user, status: :enabled, totp_enabled: true, totp_secret: DEFAULT_TOTP_SECRET)
    sign_in_as(user)
    code = ROTP::TOTP.new(DEFAULT_TOTP_SECRET).now
    post "/two_factor/challenge", params: { code: code }
    @signed_in_user = user
  end

  # 自動登入的那個使用者。個人性資料（MarginPosition / Portfolio / PriceAlert）
  # 現在有 user 歸屬，request spec 建測試資料時必須掛在這個人身上，
  # 否則 controller 的 current_user scope 會（正確地）看不到。
  def signed_in_user
    @signed_in_user
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request

  config.before(:each, type: :request) do |example|
    next if example.metadata[:skip_auto_auth]

    sign_in_and_pass_totp!
  end
end
