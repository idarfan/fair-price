# frozen_string_literal: true

# Serves the 期權小學堂 static lesson pages from private/csp_lessons/ — these
# used to live under public/csp/ where Rack's static-file middleware served
# them before the request ever reached a controller, bypassing both the
# login gate (ApplicationController#enforce_auth_gate) and page-view tracking.
# Routing them through a controller fixes both.
class CspLessonsController < ApplicationController
  ROOT = Rails.root.join("private", "csp_lessons")

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
