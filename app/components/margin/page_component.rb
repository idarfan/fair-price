# frozen_string_literal: true

class Margin::PageComponent < ApplicationComponent
  def view_template
    div(
      id:    "margin-root",
      class: "flex-1 min-w-0 min-h-0 overflow-hidden bg-gray-900"
    ) do
      plain "載入中…（若持續顯示此訊息，請開啟瀏覽器 DevTools → Console 查看錯誤）"
    end
  end
end
