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
