# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    before_action :require_admin!

    def index
      @users    = User.order(created_at: :desc)
      user_ids  = @users.map(&:id)

      @dwell_totals  = UserActivity.page_view.where(user_id: user_ids).group(:user_id).sum(:duration_ms)
      @last_activity = UserActivity.where(user_id: user_ids).group(:user_id).maximum(:created_at)
      @top_commands  = top_commands_by_user(user_ids)
    end

    def show
      @user = User.find(params[:id])
      @page_views = @user.user_activities.page_view.order(:started_at).to_a
      @commands   = @user.user_activities.command.order(started_at: :desc).to_a
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

    def top_commands_by_user(user_ids)
      counts = UserActivity.command.recent.where(user_id: user_ids)
                            .group(:user_id, :action_name).count

      counts.each_with_object(Hash.new { |h, k| h[k] = [] }) do |((user_id, action_name), count), acc|
        acc[user_id] << [ action_name, count ]
      end.transform_values { |pairs| pairs.sort_by { |(_, count)| -count }.first(3) }
    end
  end
end
