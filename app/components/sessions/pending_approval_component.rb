# frozen_string_literal: true

class Sessions::PendingApprovalComponent < ApplicationComponent
  def view_template
    div(class: "max-w-sm mx-auto mt-24 bg-white border border-gray-200 rounded-xl shadow-sm p-8 text-center") do
      div(class: "text-3xl mb-2") { plain("⏳") }
      h1(class: "text-xl font-bold text-gray-900 mb-2") { plain("帳號審核中") }
      p(class: "text-sm text-gray-500 mb-6") { plain("您的帳號正在等待管理員核准，請稍後再試。") }

      form(action: "/logout", method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        input(type: "hidden", name: "_method", value: "delete")
        button(
          type: "submit",
          class: "text-sm text-gray-500 hover:text-gray-700 underline"
        ) { plain("登出") }
      end
    end
  end
end
