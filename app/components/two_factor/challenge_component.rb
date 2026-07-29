# frozen_string_literal: true

class TwoFactor::ChallengeComponent < ApplicationComponent
  # @param locked_until [Time, nil] When the lockout (if any) expires
  def initialize(locked_until: nil)
    @locked_until = locked_until
  end

  def view_template
    div(class: "max-w-sm mx-auto mt-24 bg-white border border-gray-200 rounded-xl shadow-sm p-8") do
      h1(class: "text-xl font-bold text-gray-900 mb-1 text-center") { plain("兩步驟驗證") }

      if @locked_until
        p(class: "text-sm text-red-600 text-center") do
          plain("嘗試次數過多，請於 #{@locked_until.strftime('%H:%M:%S')} 後再試")
        end
      else
        p(class: "text-sm text-gray-500 mb-6 text-center") { plain("輸入 App 顯示的 6 碼驗證碼，或使用備用碼") }

        form(action: "/two_factor/challenge", method: "post") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          input(
            type: "text", name: "code",
            inputmode: "numeric", autocomplete: "one-time-code",
            placeholder: "6 碼驗證碼或備用碼",
            class: "w-full text-center text-lg tracking-widest border border-gray-300 rounded-lg px-4 py-2.5 mb-4 focus:outline-none focus:border-blue-500"
          )
          button(
            type: "submit",
            class: "w-full bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2.5 transition-colors"
          ) { plain("驗證") }
        end
      end
    end
  end
end
