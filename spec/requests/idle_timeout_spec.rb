# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Idle session timeout", :skip_auto_auth, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  it "keeps a normal user logged in within the 2 hour idle window" do
    sign_in_and_pass_totp!

    travel 1.hour
    get "/momentum"
    expect(response).to have_http_status(:ok)
  end

  it "forces re-login after 2 hours of idle for a normal user" do
    sign_in_and_pass_totp!

    travel 2.hours + 1.minute
    get "/momentum"
    expect(response).to redirect_to(login_path)
  end

  it "never forces re-login for the exempt email regardless of idle time" do
    user = create(:user, status: :enabled, totp_enabled: true, totp_secret: AuthHelpers::DEFAULT_TOTP_SECRET,
                          email: ApplicationController::IDLE_TIMEOUT_EXEMPT_EMAIL)
    sign_in_and_pass_totp!(user: user)

    travel 10.hours
    get "/momentum"
    expect(response).to have_http_status(:ok)
  end
end
