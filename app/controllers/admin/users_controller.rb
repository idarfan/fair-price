# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    before_action :require_admin!

    def index
      @users = User.order(created_at: :desc)
    end

    def approve
      user = User.find(params[:id])
      user.update!(status: :enabled, approved_at: Time.current)
      redirect_to admin_users_path, notice: "已核准 #{user.email}"
    end

    def disable
      user = User.find(params[:id])
      user.update!(status: :disabled)
      user.bump_session_version!
      redirect_to admin_users_path, notice: "已停用 #{user.email}"
    end

    def reactivate
      user = User.find(params[:id])
      user.update!(status: :enabled)
      redirect_to admin_users_path, notice: "已重新啟用 #{user.email}"
    end

    private

    def require_admin!
      head :not_found unless current_user&.admin?
    end
  end
end
