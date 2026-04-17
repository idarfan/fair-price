# frozen_string_literal: true

class Options::PageComponent < ApplicationComponent
  def initialize(symbol: nil)
    @symbol = symbol
  end

  def view_template
    div(
      id:    "options-root",
      class: "flex-1 min-w-0 min-h-0 overflow-hidden bg-gray-50 flex flex-col",
      data:  { symbol: (@symbol || "").to_json }
    ) do
      plain "載入中…（若持續顯示此訊息，請開啟瀏覽器 DevTools → Console 查看錯誤）"
    end
  end
end
