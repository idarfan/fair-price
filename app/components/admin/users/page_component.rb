# frozen_string_literal: true

class Admin::Users::PageComponent < ApplicationComponent
  # @param users [ActiveRecord::Relation<User>]
  # @param current_admin [User]
  # @param dwell_totals [Hash<Integer, Integer>] user_id => summed page_view duration_ms（全部歷史）
  # @param daily_dwell [Hash<Integer, Array<Array(Date, Integer)>>] user_id => 近7天 [date, duration_ms]，新到舊
  # @param last_activity [Hash<Integer, Time>] user_id => most recent UserActivity#created_at
  # @param top_commands [Hash<Integer, Array<Array(String, Integer)>>] user_id => top-3 [action_name, count]
  def initialize(users:, current_admin:, dwell_totals: {}, daily_dwell: {}, last_activity: {}, top_commands: {})
    @users         = users
    @current_admin = current_admin
    @dwell_totals  = dwell_totals
    @daily_dwell   = daily_dwell
    @last_activity = last_activity
    @top_commands  = top_commands
  end

  def view_template
    div(class: "space-y-5") do
      render_header
      render_table
    end
  end

  private

  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") do
        span(class: "mr-2") { plain("🛡️") }
        plain("帳戶管理")
      end
      p(class: "text-sm text-gray-400 mt-0.5") { plain("核准新註冊帳號、停用或重新啟用既有帳號") }
    end
  end

  def render_table
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          render_table_header
          tbody do
            @users.each do |user|
              render Admin::Users::RowComponent.new(
                user:             user,
                is_self:          user.id == @current_admin.id,
                dwell_ms:         @dwell_totals[user.id],
                daily_dwell:      @daily_dwell[user.id] || [],
                top_commands:     @top_commands[user.id] || [],
                last_activity_at: @last_activity[user.id]
              )
            end
          end
        end
      end
    end
  end

  def render_table_header
    thead(class: "bg-gray-50 border-b border-gray-100") do
      tr do
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("Email") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("註冊時間") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("狀態") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("TOTP") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("最後登入") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("累積停留時間") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("近7天常用指令") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("最後活動時間") }
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("操作") }
      end
    end
  end
end
