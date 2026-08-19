class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  GATE_EXEMPT_PREFIXES = %w[/login /logout /auth /up /api /track].freeze

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
    return if GATE_EXEMPT_PREFIXES.any? { |prefix| request.path.start_with?(prefix) }
    return redirect_to login_path unless logged_in?
    return if enforce_idle_timeout
    return if enforce_absolute_timeout

    if current_user.disabled?
      return if request.path == account_disabled_path

      return redirect_to account_disabled_path
    end

    return if request.path.start_with?("/two_factor/")
    return if current_user.admin?

    unless current_user.totp_enabled?
      return redirect_to "/two_factor/setup"
    end

    unless session[:totp_verified]
      return redirect_to "/two_factor/challenge"
    end

    return unless current_user.pending?
    return if request.path == "/pending_approval"

    redirect_to "/pending_approval"
  end

  # 回傳 true 代表已經處理完（逾時導回登入頁），呼叫端應立即 return。
  def enforce_idle_timeout
    return false if current_user.email == IDLE_TIMEOUT_EXEMPT_EMAIL

    last_seen_at = session[:last_seen_at]
    session[:last_seen_at] = Time.current.to_i

    return false if last_seen_at.nil?
    return false if Time.current.to_i - last_seen_at <= IDLE_TIMEOUT.to_i

    reset_session
    redirect_to login_path, alert: "閒置超過 2 小時，請重新登入"
    true
  end

  # 回傳 true 代表已經處理完（登入滿 24 小時導回登入頁），呼叫端應立即 return。
  def enforce_absolute_timeout
    return false if current_user.email == IDLE_TIMEOUT_EXEMPT_EMAIL

    login_at = session[:login_at]
    return false if login_at.nil?
    return false if Time.current.to_i - login_at <= ABSOLUTE_SESSION_TIMEOUT.to_i

    reset_session
    redirect_to login_path, alert: "登入已滿 24 小時，請重新登入"
    true
  end
end
