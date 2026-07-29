# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Track", type: :request do
  describe "POST /track/page_view" do
    it "creates a page_view UserActivity for the logged-in user" do
      expect {
        post "/track/page_view", params: {
          activity_token: "tok-1", path: "/momentum", referrer_path: "/", duration_ms: "1500"
        }
      }.to change(UserActivity, :count).by(1)

      activity = UserActivity.last
      expect(activity.kind).to eq("page_view")
      expect(activity.path).to eq("/momentum")
      expect(activity.referrer_path).to eq("/")
      expect(activity.duration_ms).to eq(1500)
    end

    it "upserts by activity_token instead of creating duplicates (heartbeat)" do
      post "/track/page_view", params: { activity_token: "tok-2", path: "/momentum", duration_ms: "1000" }

      expect {
        post "/track/page_view", params: { activity_token: "tok-2", path: "/momentum", duration_ms: "5000" }
      }.not_to change(UserActivity, :count)

      expect(UserActivity.find_by(activity_token: "tok-2").duration_ms).to eq(5000)
    end

    it "ignores unauthenticated requests without writing to the DB" do
      delete "/logout"

      expect {
        post "/track/page_view", params: { activity_token: "tok-3", path: "/momentum", duration_ms: "1000" }
      }.not_to change(UserActivity, :count)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /track/command" do
    it "creates a command UserActivity with full metadata" do
      metadata = { "symbol" => "NOK", "delta_min" => "0.6", "delta_max" => "0.9" }

      expect {
        post "/track/command", params: { action_name: "leaps_filter", metadata: metadata.to_json }
      }.to change(UserActivity, :count).by(1)

      activity = UserActivity.last
      expect(activity.kind).to eq("command")
      expect(activity.action_name).to eq("leaps_filter")
      expect(activity.metadata).to eq(metadata)
    end

    it "ignores unauthenticated requests" do
      delete "/logout"

      expect {
        post "/track/command", params: { action_name: "leaps_filter", metadata: "{}" }
      }.not_to change(UserActivity, :count)
    end
  end
end
