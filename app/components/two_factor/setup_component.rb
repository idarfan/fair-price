# frozen_string_literal: true

class TwoFactor::SetupComponent < ApplicationComponent
  # @param secret [String] Base32 TOTP secret (also usable for manual entry)
  # @param qr_svg [String] Pre-rendered SVG markup for the provisioning QR code
  def initialize(secret:, qr_svg:)
    @secret = secret
    @qr_svg = qr_svg
  end

  def view_template
    div(class: "max-w-md mx-auto mt-16 bg-white border border-gray-200 rounded-xl shadow-sm p-8") do
      h1(class: "text-xl font-bold text-gray-900 mb-1 text-center") { plain("設定兩步驟驗證") }
      p(class: "text-sm text-gray-500 mb-6 text-center") { plain("用 Google Authenticator 等 App 掃描下方 QR code") }

      div(class: "flex justify-center mb-4") { raw @qr_svg.html_safe }

      div(class: "bg-gray-50 rounded-lg p-3 mb-6 text-center") do
        p(class: "text-xs text-gray-400 mb-1") { plain("無法掃描？手動輸入這組金鑰：") }
        code(class: "text-sm font-mono text-gray-700 break-all") { plain(@secret) }
      end

      form(action: "/two_factor/setup", method: "post") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
        label(class: "block text-sm text-gray-600 mb-1", for: "code") { plain("輸入 App 顯示的 6 碼驗證碼") }
        input(
          type: "text", name: "code", id: "code",
          inputmode: "numeric", autocomplete: "one-time-code", maxlength: "6",
          class: "w-full text-center text-lg tracking-widest border border-gray-300 rounded-lg px-4 py-2.5 mb-4 focus:outline-none focus:border-blue-500"
        )
        button(
          type: "submit",
          class: "w-full bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2.5 transition-colors"
        ) { plain("驗證並啟用") }
      end
    end
  end
end
