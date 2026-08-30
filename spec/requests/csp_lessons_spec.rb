# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CSP lessons", :skip_auto_auth, type: :request do
  describe "unauthenticated" do
    it "redirects /csp/index.html to /login instead of serving the file" do
      get "/csp/index.html"
      expect(response).to redirect_to(login_path)
    end
  end

  describe "logged in" do
    it "serves the lesson page and records a page_view activity" do
      user = sign_in_and_pass_totp!

      expect {
        get "/csp/index.html"
      }.to change { user.user_activities.where(kind: :page_view, path: "/csp/index.html").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end

    it "redirects the bare /csp path to /csp/index.html" do
      sign_in_and_pass_totp!

      get "/csp"
      expect(response).to redirect_to("/csp/index.html")
    end

    it "blocks path traversal outside private/csp_lessons" do
      sign_in_and_pass_totp!

      get "/csp/../../config/master.key"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a file that isn't in the whitelisted lesson set" do
      sign_in_and_pass_totp!

      get "/csp/does-not-exist.html"
      expect(response).to have_http_status(:not_found)
    end
  end
end
