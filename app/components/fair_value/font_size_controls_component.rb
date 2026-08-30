# frozen_string_literal: true

class FairValue::FontSizeControlsComponent < ApplicationComponent
  # btn_text 是按鈕自己的字級（不是它套用的全站字級），由小到大排出階梯。
  #
  # 寫成字面 class 而不是 "text-[#{...}px]" 插值：Tailwind v4 的掃描器
  # 只認得原始碼裡出現過的完整字串，插值組出來的 class 不會被編進 CSS
  # （見 memory feedback_tailwind_v4_dynamic_class）。
  SIZES = [
    { px: 18, idx: 0, btn_text: "text-[10px]" },
    { px: 19, idx: 1, btn_text: "text-[12px]" },
    { px: 20, idx: 2, btn_text: "text-[14px]" },
    { px: 21, idx: 3, btn_text: "text-[16px]" },
    { px: 22, idx: 4, btn_text: "text-[18px]" }
  ].freeze
  STORAGE_KEY = "fairprice:font-size"

  # layout 的「繪製前還原字級」inline script 與下面的 behavior 都從這裡取值，
  # 避免兩邊各自寫死而漂移（曾經發生：白名單停在 14–18，按鈕卻是 18–22，
  # 導致選 19–22 的使用者換頁後字級被打回預設）。
  def self.allowed_sizes
    SIZES.map { |s| s[:px].to_s }
  end

  def view_template
    div(class: "flex items-center gap-1", id: "font-size-controls") do
      span(class: "text-xs text-gray-400 mr-0.5 select-none") { plain("字體調整") }
      SIZES.each do |s|
        button(
          type: "button",
          data: { size: s[:px] },
          title: "字體 #{s[:px]}px",
          # 原本用 inline style 設字級與行高。CSP 收斂：style-src 拿掉
          # :unsafe_inline 之後 style 屬性會被擋，且 nonce 對屬性無效。
          # leading-[1.2] 取代原本被 inline style 蓋掉的 leading-none。
          class: "font-size-btn px-1 py-0.5 rounded transition-colors font-bold " \
                 "text-gray-400 hover:text-gray-700 hover:bg-gray-100 " \
                 "leading-[1.2] #{s[:btn_text]}"
        ) { plain("A") }
      end
    end
    render_script
  end

  private

  def render_script
    # JavaScript 已搬到 app/frontend/behaviors/fontSizeControls.js（稽核 H-3 Wave 2）。
    # 原本的 Ruby 插值改成 data attribute 傳入。
    div(data: { behavior: "font-size-controls", storage_key: STORAGE_KEY,
                sizes: self.class.allowed_sizes.to_json })
  end
end
