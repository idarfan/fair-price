class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  GATE_EXEMPT_PREFIXES = %w[/login /logout /auth /up /api].freeze

  helper_method :current_user, :logged_in?

  before_action :enforce_auth_gate

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def enforce_auth_gate
    return if GATE_EXEMPT_PREFIXES.any? { |prefix| request.path.start_with?(prefix) }
    return redirect_to login_path unless logged_in?

    if current_user.disabled?
      return if request.path == account_disabled_path

      return redirect_to account_disabled_path
    end

    return if request.path.start_with?("/two_factor/")

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
end
