# frozen_string_literal: true

class Admin::Users::RowComponent < ApplicationComponent
  STATUS_STYLES = {
    "pending"  => "bg-yellow-50 text-yellow-700",
    "enabled"  => "bg-green-50 text-green-700",
    "disabled" => "bg-gray-100 text-gray-500"
  }.freeze
  STATUS_LABELS = {
    "pending"  => "待審核",
    "enabled"  => "已啟用",
    "disabled" => "已停用"
  }.freeze

  # @param user [User]
  # @param is_self [Boolean] Whether this row is the currently signed-in admin
  # @param dwell_ms [Integer, nil] Accumulated page_view duration_ms
  # @param top_commands [Array<Array(String, Integer)>] [[action_name, count], ...] in the last 7 days
  # @param last_activity_at [Time, nil] Most recent UserActivity#created_at (page_view or command)
  def initialize(user:, is_self:, dwell_ms: nil, top_commands: [], last_activity_at: nil)
    @user             = user
    @is_self          = is_self
    @dwell_ms         = dwell_ms
    @top_commands     = top_commands
    @last_activity_at = last_activity_at
  end

  def view_template
    tr(class: "border-t border-gray-100") do
      td(class: "px-3 py-2.5 text-sm text-blue-600") do
        a(href: "/admin/users/#{@user.id}", class: "hover:underline") { plain(@user.email) }
      end
      td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(@user.created_at.strftime("%Y-%m-%d")) }
      td(class: "px-3 py-2.5") do
        span(class: "px-2 py-0.5 rounded-full text-xs font-medium #{STATUS_STYLES.fetch(@user.status)}") do
          plain(STATUS_LABELS.fetch(@user.status))
        end
      end
      td(class: "px-3 py-2.5 text-sm #{@user.totp_enabled? ? 'text-green-600' : 'text-gray-400'}") do
        plain(@user.totp_enabled? ? "已啟用" : "未啟用")
      end
      td(class: "px-3 py-2.5 text-sm text-gray-500") do
        plain(@user.last_login_at&.strftime("%Y-%m-%d %H:%M") || "—")
      end
      td(class: "px-3 py-2.5 text-sm text-gray-500") { plain(fmt_duration_ms(@dwell_ms)) }
      td(class: "px-3 py-2.5 text-sm text-gray-500") { render_top_commands }
      td(class: "px-3 py-2.5 text-sm text-gray-500") do
        plain(@last_activity_at&.strftime("%Y-%m-%d %H:%M") || "—")
      end
      td(class: "px-3 py-2.5") { render_actions }
    end
  end

  private

  def render_top_commands
    return plain("—") if @top_commands.blank?

    div(class: "space-y-0.5") do
      @top_commands.each do |action_name, count|
        div(class: "text-xs") { plain("#{action_name} × #{count}") }
      end
    end
  end

  def render_actions
    case @user.status
    when "pending"
      action_form(path: "/admin/users/#{@user.id}/approve", label: "核准", style: "text-green-600 hover:text-green-700")
    when "enabled"
      action_form(path: "/admin/users/#{@user.id}/disable", label: "停用", style: "text-red-600 hover:text-red-700") unless @is_self
    when "disabled"
      action_form(path: "/admin/users/#{@user.id}/reactivate", label: "重新啟用", style: "text-blue-600 hover:text-blue-700")
    end
  end

  def action_form(path:, label:, style:)
    form(action: path, method: "post") do
      input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
      input(type: "hidden", name: "_method", value: "patch")
      button(type: "submit", class: "text-sm font-medium #{style}") { plain(label) }
    end
  end
end
