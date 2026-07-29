# frozen_string_literal: true

class Admin::Users::PageComponent < ApplicationComponent
  # @param users [ActiveRecord::Relation<User>]
  # @param current_admin [User]
  def initialize(users:, current_admin:)
    @users         = users
    @current_admin = current_admin
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
              render Admin::Users::RowComponent.new(user: user, is_self: user.id == @current_admin.id)
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
        th(class: "px-3 py-2.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wide") { plain("操作") }
      end
    end
  end
end
