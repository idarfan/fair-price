# frozen_string_literal: true

# Serves the 期權小學堂 static lesson pages from private/csp_lessons/ — these
# used to live under public/csp/ where Rack's static-file middleware served
# them before the request ever reached a controller, bypassing both the
# login gate (ApplicationController#enforce_auth_gate) and page-view tracking.
# Routing them through a controller fixes both.
class CspLessonsController < ApplicationController
  ROOT = Rails.root.join("private", "csp_lessons")

  # 這些教材頁是手寫的靜態 HTML（含 SVG 漫畫排版），是 send_file 原樣送出、
  # **沒有任何使用者輸入被渲染進去**——攻擊者無法在其中注入內容，
  # 除非他已經能寫入這個 repo。
  #
  # 因此 :unsafe_inline 在這裡保留，讓應用程式本體可以收緊。
  # 這是刻意的分區，不是遺漏。
  #
  # 為什麼 script-src 也要（2026-09-08 補）：這 12 頁共有 350 個內嵌事件屬性
  # （onclick／oninput／onchange），朗讀、字級調整、名詞說明全靠它們。
  # nonce 對事件屬性無效——跟 style="..." 一樣，只對 <script> 區塊有效，
  # 所以「注入 nonce」那招救得了 <script> 卻救不了 onclick。要改成
  # addEventListener 得動 350 處、12 個檔案，風險遠高於這裡開一個分區例外。
  content_security_policy do |policy|
    policy.style_src  :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    policy.script_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"
  end

  # 光是上面兩行不夠。全域設定把 script-src 與 style-src 都列進
  # nonce_directives，中介層會再附加一個 'nonce-...'，而 CSP 規範明訂：
  # **一旦出現 nonce，同一個 directive 的 'unsafe-inline' 就會被瀏覽器忽略**。
  # 兩者並存的結果是宣告了 unsafe_inline 卻完全沒有作用——畫面沒有任何錯誤，
  # 只有 console 裡一長串違規，極難聯想到是 CSP。
  #
  # 因此這個 controller 的回應完全不帶 nonce。
  before_action { request.content_security_policy_nonce_directives = [] }

  def show
    relative_path = params[:path].presence || "index.html"
    file_path = ROOT.join(relative_path).expand_path

    unless file_path.to_s.start_with?("#{ROOT}/") && file_path.file?
      return head :not_found
    end

    log_page_view(relative_path)

    send_file file_path, disposition: "inline", type: content_type_for(file_path)
  end

  private

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
