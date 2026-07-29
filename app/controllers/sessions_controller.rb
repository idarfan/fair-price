# frozen_string_literal: true

class SessionsController < ApplicationController
  ADMIN_EMAILS = -> { ENV.fetch("ADMIN_EMAILS", "").split(",").map(&:strip) }

  def new
  end

  def google_callback
    auth = request.env["omniauth.auth"]

    user = User.find_or_create_by!(google_uid: auth.uid) do |u|
      u.email = auth.info.email
      if ADMIN_EMAILS.call.include?(auth.info.email)
        u.status      = :enabled
        u.admin       = true
        u.approved_at = Time.current
      end
    end

    session[:user_id]       = user.id
    session[:totp_verified] = false

    if user.disabled?
      redirect_to account_disabled_path and return
    end

    if user.totp_enabled?
      redirect_to "/two_factor/challenge"
    else
      redirect_to "/two_factor/setup"
    end
  end

  def failure
    redirect_to login_path, alert: "登入失敗：#{params[:message]}"
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "已登出"
  end

  def account_disabled
  end

  def pending_approval
  end
end
