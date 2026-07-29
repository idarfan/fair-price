# frozen_string_literal: true

class AccountSecurity::PageComponent < ApplicationComponent
  # @param user [User]
  def initialize(user:)
    @user = user
  end

  def view_template
    div(class: "max-w-md mx-auto mt-16 bg-white border border-gray-200 rounded-xl shadow-sm p-8 space-y-6") do
      h1(class: "text-xl font-bold text-gray-900") { plain("帳戶安全") }

      div(class: "flex items-center justify-between bg-gray-50 rounded-lg px-4 py-3") do
        span(class: "text-sm text-gray-600") { plain("兩步驟驗證") }
        span(class: "text-sm font-medium #{@user.totp_enabled? ? 'text-green-600' : 'text-gray-400'}") do
          plain(@user.totp_enabled? ? "已啟用" : "未啟用")
        end
      end

      render_backup_codes_form
      render_logout_all_form
    end
  end

  private

  def render_backup_codes_form
    div(class: "border-t border-gray-100 pt-5") do
      p(class: "text-sm font-medium text-gray-700 mb-1") { plain("備用碼") }
      p(class: "text-xs text-gray-400 mb-3") { plain("重新產生後，舊的 10 組備用碼將立即全部失效。") }
      form(action: "/settings/security/backup_codes", method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(
          type: "submit",
          class: "w-full bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium rounded-lg px-5 py-2.5 transition-colors"
        ) { plain("重新產生備用碼") }
      end
    end
  end

  def render_logout_all_form
    div(class: "border-t border-gray-100 pt-5") do
      p(class: "text-sm font-medium text-gray-700 mb-1") { plain("登出所有裝置") }
      p(class: "text-xs text-gray-400 mb-3") { plain("將立即結束所有裝置上的登入狀態，包含目前這台。") }
      form(action: "/settings/security/logout_all", method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(
          type: "submit",
          class: "w-full bg-red-50 hover:bg-red-100 text-red-700 font-medium rounded-lg px-5 py-2.5 transition-colors"
        ) { plain("登出所有裝置") }
      end
    end
  end
end
