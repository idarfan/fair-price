# frozen_string_literal: true

# Serves the 期權小學堂 static lesson pages from private/csp_lessons/ — these
# used to live under public/csp/ where Rack's static-file middleware served
# them before the request ever reached a controller, bypassing both the
# login gate (ApplicationController#enforce_auth_gate) and page-view tracking.
# Routing them through a controller fixes both.
class CspLessonsController < ApplicationController
  ROOT = Rails.root.join("private", "csp_lessons")

  # 這些教材頁是手寫的靜態 HTML（含 SVG 漫畫排版），內嵌樣式約 840 處，
  # 而且是 send_file 原樣送出、**沒有任何使用者輸入被渲染進去**——
  # 攻擊者無法在其中注入內容，除非他已經能寫入這個 repo。
  #
  # 因此 style-src 的 :unsafe_inline 在這裡保留，讓應用程式本體可以收緊。
  # 這是刻意的分區，不是遺漏。
  content_security_policy do |policy|
    policy.style_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"
  end

  # 光是上面那行不夠。全域設定把 style-src 列進 nonce_directives，
  # 中介層會再附加一個 'nonce-...'，而 CSP 規範明訂：**style-src 一旦出現
  # nonce，'unsafe-inline' 就會被瀏覽器忽略**。結果是這裡宣告了 unsafe_inline，
  # 送出的標頭兩者並存，教材頁那 840 處內嵌樣式仍然全部被擋——整頁沒有樣式，
  # 而且不會有任何錯誤，只有 console 裡一長串 CSP 違規。
  #
  # nonce 對 style="..." 屬性本來就無效（只對 <style> 區塊有效），
  # 所以這裡把 style-src 移出 nonce 清單不會損失任何防護。
  before_action do
    request.content_security_policy_nonce_directives = %w[script-src]
  end

  def show
    relative_path = params[:path].presence || "index.html"
    file_path = ROOT.join(relative_path).expand_path

    unless file_path.to_s.start_with?("#{ROOT}/") && file_path.file?
      return head :not_found
    end

    log_page_view(relative_path)

    # HTML 要先注入 nonce 才送出（見 nonce_for_inline_scripts）；
    # 圖片、SVG 等其餘檔案照舊走 send_file，不進記憶體。
    if file_path.extname.casecmp(".html").zero?
      render html: nonce_for_inline_scripts(file_path.read).html_safe, layout: false
    else
      send_file file_path, disposition: "inline", type: content_type_for(file_path)
    end
  end

  private

  # 這些教材頁的課程資料與互動邏輯都在內嵌 <script> 裡，而全域 script-src
  # 不放行 :unsafe_inline——不處理的話課程清單整片空白，畫面有樣式卻沒有內容。
  #
  # 這裡不學 style-src 那樣開 :unsafe_inline，而是把當次請求的 nonce 注入進去：
  # nonce 對 <script> 區塊是有效的（無效的只有 style="..." 屬性），
  # 因此可以在維持嚴格政策的前提下只放行這幾段自家的靜態程式碼。
  #
  # 只處理沒有 src 的 <script>：有 src 的走 script-src 的來源白名單，不需要 nonce。
  def nonce_for_inline_scripts(html)
    nonce = content_security_policy_nonce
    return html if nonce.blank?

    html.gsub(/<script(?![^>]*\bsrc=)([^>]*)>/i) do
      attrs = Regexp.last_match(1)
      attrs.match?(/\bnonce=/i) ? "<script#{attrs}>" : %(<script nonce="#{nonce}"#{attrs}>)
    end
  end

  def content_type_for(file_path)
    Rack::Mime.mime_type(file_path.extname, "application/octet-stream")
  end

  def log_page_view(relative_path)
    current_user.user_activities.create(
      kind:       :page_view,
      path:       "/csp/#{relative_path}",
      started_at: Time.current,
      ended_at:   Time.current
    )
  end
end
