# frozen_string_literal: true

# 全站 layout 都會帶「版本更新說明」彈窗（#release-notes-overlay），內容是給使用者看的
# 變更摘要，常會引用畫面上的訊息原文（例如 v20261012 寫到「已不是最新」）。
# 斷言「頁面有／沒有某段訊息」時要先把彈窗拿掉，否則負向斷言會誤報失敗、
# 正向斷言則會被彈窗文字撐成必過。
module WithoutReleaseNotes
  module_function

  def doc(html)
    Nokogiri::HTML(html).tap { |d| d.css("#release-notes-overlay").each(&:remove) }
  end

  def html(body) = doc(body).to_html
end
