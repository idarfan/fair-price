# frozen_string_literal: true

class TwoFactorController < ApplicationController
  def setup
    session[:pending_totp_secret] ||= ROTP::Base32.random
    @secret = session[:pending_totp_secret]
    @qr_svg = build_qr_svg(@secret)
  end

  def create_setup
    secret = session[:pending_totp_secret]
    totp   = ROTP::TOTP.new(secret, issuer: "FairPrice-Ohmy")

    if totp.verify(params[:code].to_s, drift_behind: 30, drift_ahead: 30)
      current_user.update!(totp_secret: secret, totp_enabled: true)
      session[:backup_codes_plaintext] = current_user.generate_backup_codes!
      session.delete(:pending_totp_secret)
      redirect_to "/two_factor/backup_codes"
    else
      flash.now[:alert] = "驗證碼錯誤，請重新輸入"
      @secret = secret
      @qr_svg = build_qr_svg(secret)
      render :setup, status: :unprocessable_entity
    end
  end

  def backup_codes
    @codes = session.delete(:backup_codes_plaintext)
  end

  def challenge
    @locked_until = totp_locked_until
  end

  def create_challenge
    if totp_locked_until
      flash.now[:alert] = "嘗試次數過多，請稍後再試"
      render :challenge, status: :too_many_requests and return
    end

    code     = params[:code].to_s
    totp     = ROTP::TOTP.new(current_user.totp_secret, issuer: "FairPrice-Ohmy")
    verified = totp.verify(code, drift_behind: 30, drift_ahead: 30).present? ||
               current_user.consume_backup_code!(code)

    if verified
      session[:totp_verified]   = true
      session[:totp_fail_count] = 0
      current_user.update!(last_login_at: Time.current)
      redirect_to root_path
    else
      session[:totp_fail_count] = session[:totp_fail_count].to_i + 1
      if session[:totp_fail_count] >= 5
        session[:totp_locked_until] = 5.minutes.from_now.iso8601
        session[:totp_fail_count]   = 0
      end
      flash.now[:alert] = "驗證碼錯誤"
      render :challenge, status: :unprocessable_entity
    end
  end

  private

  def build_qr_svg(secret)
    uri = ROTP::TOTP.new(secret, issuer: "FairPrice-Ohmy").provisioning_uri("FairPrice-Ohmy")
    RQRCode::QRCode.new(uri).as_svg(standalone: true, module_size: 4, fill: "ffffff", color: "000000")
  end

  def totp_locked_until
    locked = session[:totp_locked_until]
    return nil unless locked

    time = Time.zone.parse(locked)
    if Time.current >= time
      session.delete(:totp_locked_until)
      return nil
    end
    time
  end
end
