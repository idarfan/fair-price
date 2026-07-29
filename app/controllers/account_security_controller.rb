# frozen_string_literal: true

class AccountSecurityController < ApplicationController
  def show
  end

  def regenerate_backup_codes
    session[:backup_codes_plaintext] = current_user.generate_backup_codes!
    redirect_to "/two_factor/backup_codes"
  end

  def logout_all_devices
    current_user.bump_session_version!
    reset_session
    redirect_to login_path, notice: "已登出所有裝置，請重新登入"
  end
end
