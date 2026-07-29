# frozen_string_literal: true

class TwoFactor::BackupCodesComponent < ApplicationComponent
  # @param codes [Array<String>, nil] Plaintext backup codes, only available immediately after generation
  def initialize(codes:)
    @codes = codes
  end

  def view_template
    div(class: "max-w-md mx-auto mt-16 bg-white border border-gray-200 rounded-xl shadow-sm p-8") do
      if @codes
        h1(class: "text-xl font-bold text-gray-900 mb-1 text-center") { plain("備用碼") }
        p(class: "text-sm text-gray-500 mb-6 text-center") { plain("請妥善保存，離開此頁後將無法再次查看") }

        div(class: "grid grid-cols-2 gap-2 mb-6") do
          @codes.each do |backup_code|
            code(class: "block text-center text-sm font-mono bg-gray-50 border border-gray-200 rounded-lg py-2") { plain(backup_code) }
          end
        end

        a(href: "/", class: "block w-full text-center bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2.5 transition-colors") { plain("我已保存，繼續") }
      else
        h1(class: "text-xl font-bold text-gray-900 mb-2 text-center") { plain("備用碼已無法再次查看") }
        p(class: "text-sm text-gray-500 text-center") { plain("如需重新產生，請洽管理員或至帳戶安全頁操作。") }
      end
    end
  end
end
