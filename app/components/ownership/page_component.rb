# frozen_string_literal: true

class Ownership::PageComponent < ApplicationComponent
  def initialize(symbols:, selected:)
    @symbols  = symbols
    @selected = selected
  end

  def view_template
    div(
      id:    "ownership-root",
      class: "flex-1 p-8 text-gray-500 text-sm",
      data:  { symbols: @symbols.to_json }
    ) do
      plain "載入中…（若持續顯示此訊息，請開啟瀏覽器 DevTools → Console 查看錯誤）"
    end
  end
end
