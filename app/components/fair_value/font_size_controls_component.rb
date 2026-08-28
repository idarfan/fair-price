# frozen_string_literal: true

class FairValue::FontSizeControlsComponent < ApplicationComponent
  SIZES = [
    { px: 18, idx: 0 },
    { px: 19, idx: 1 },
    { px: 20, idx: 2 },
    { px: 21, idx: 3 },
    { px: 22, idx: 4 }
  ].freeze
  STORAGE_KEY = "fairprice:font-size"

  def view_template
    div(class: "flex items-center gap-1", id: "font-size-controls") do
      span(class: "text-xs text-gray-400 mr-0.5 select-none") { plain("字體調整") }
      SIZES.each do |s|
        button(
          type: "button",
          data: { size: s[:px] },
          title: "字體 #{s[:px]}px",
          class: "font-size-btn px-1 py-0.5 rounded transition-colors font-bold text-gray-400 hover:text-gray-700 hover:bg-gray-100 leading-none",
          style: "font-size: #{10 + s[:idx] * 2}px; line-height: 1.2;"
        ) { plain("A") }
      end
    end
    render_script
  end

  private

  def render_script
    # JavaScript 已搬到 app/frontend/behaviors/fontSizeControls.js（稽核 H-3 Wave 2）。
    # 原本的 Ruby 插值改成 data attribute 傳入。
    div(data: { behavior: "font-size-controls", storage_key: STORAGE_KEY })
  end
end
