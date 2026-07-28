# frozen_string_literal: true

class Sessions::LoginPageComponent < ApplicationComponent
  def view_template
    div(class: "max-w-sm mx-auto mt-24 bg-white border border-gray-200 rounded-xl shadow-sm p-8 text-center") do
      div(class: "text-3xl mb-2") { plain("📊") }
      h1(class: "text-xl font-bold text-gray-900 mb-1") { plain("FairPrice") }
      p(class: "text-sm text-gray-500 mb-6") { plain("請使用 Google 帳號登入") }

      form(action: "/auth/google_oauth2", method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        button(
          type: "submit",
          class: "w-full bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2.5 transition-colors"
        ) { plain("使用 Google 登入") }
      end
    end
  end
end
