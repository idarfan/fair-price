class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  # 不需要登入就能存取的路徑。用 anchored regex 而非 start_with? 前綴比對，
  # 否則像 /logout_backdoor、/upgrade 這種路徑會意外命中白名單。
  #
  # 注意：/api 刻意「不在」這份名單裡。API 與 UI 共用同一份 session 與 2FA 閘門，
  # 只是把導頁換成 JSON 狀態碼（見 JsonAuthGate）。
  GATE_EXEMPT_PATHS = %r{\A/(login|logout|auth|up|track)(/|\z)}

  # 閒置逾時：連續 2 小時沒有任何請求就強制重新登入；此帳號不受限。
  IDLE_TIMEOUT = 2.hours
  # 每日強制登出：不論有沒有活動，登入滿 24 小時就強制重新登入；此帳號不受限。
  ABSOLUTE_SESSION_TIMEOUT = 24.hours
  IDLE_TIMEOUT_EXEMPT_EMAIL = "mr.idarfan@gmail.com"

  helper_method :current_user, :logged_in?

  before_action :enforce_auth_gate

  private

  def current_user
    return @current_user if defined?(@current_user)

    user = User.find_by(id: session[:user_id])
    if user && session[:session_version] != user.session_version
      reset_session
      user = nil
    end
    @current_user = user
  end

  def logged_in?
    current_user.present?
  end

  def enforce_auth_gate
    return if request.path.match?(GATE_EXEMPT_PATHS)
    return gate_deny(:unauthenticated) unless logged_in?
    return if enforce_idle_timeout
    return if enforce_absolute_timeout

    if current_user.disabled?
      return if request.path == account_disabled_path

      return gate_deny(:account_disabled)
    end

    return if request.path.start_with?("/two_factor/")
    return if current_user.admin?

    return gate_deny(:totp_setup_required)        unless current_user.totp_enabled?
    return gate_deny(:totp_verification_required) unless session[:totp_verified]
    return unless current_user.pending?
    return if request.path == "/pending_approval"

    gate_deny(:pending_approval)
  end

  # 閘門拒絕請求的方式。HTML 請求導頁；API controller 覆寫成回傳 JSON 狀態碼
  # （見 JsonAuthGate），這樣兩邊共用同一套閘門判斷邏輯，不會各寫一份而漂移。
  def gate_deny(reason, alert: nil)
    path = case reason
    when :unauthenticated, :idle_timeout, :absolute_timeout then login_path
    when :account_disabled                                  then account_disabled_path
    when :totp_setup_required                               then "/two_factor/setup"
    when :totp_verification_required                        then "/two_factor/challenge"
    when :pending_approval                                  then "/pending_approval"
    end

    redirect_to path, alert: alert
  end

  # 回傳 true 代表已經處理完（逾時導回登入頁），呼叫端應立即 return。
  def enforce_idle_timeout
    return false if current_user.email == IDLE_TIMEOUT_EXEMPT_EMAIL

    last_seen_at = session[:last_seen_at]
    session[:last_seen_at] = Time.current.to_i

    return false if last_seen_at.nil?
    return false if Time.current.to_i - last_seen_at <= IDLE_TIMEOUT.to_i

    reset_session
    gate_deny(:idle_timeout, alert: "閒置超過 2 小時，請重新登入")
    true
  end

  # 回傳 true 代表已經處理完（登入滿 24 小時導回登入頁），呼叫端應立即 return。
  def enforce_absolute_timeout
    return false if current_user.email == IDLE_TIMEOUT_EXEMPT_EMAIL

    login_at = session[:login_at]
    return false if login_at.nil?
    return false if Time.current.to_i - login_at <= ABSOLUTE_SESSION_TIMEOUT.to_i

    reset_session
    gate_deny(:absolute_timeout, alert: "登入已滿 24 小時，請重新登入")
    true
  end
end
