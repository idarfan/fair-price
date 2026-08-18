# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Absolute (daily) session timeout", type: :request, skip_auto_auth: true do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  it "keeps a continuously active user logged in within the 24 hour window" do
    sign_in_and_pass_totp!

    # 每小時發一次請求，維持在 2 小時閒置窗內，藉此單獨驗證 24 小時上限。
    23.times do
      travel 1.hour
      get "/momentum"
      expect(response).to have_http_status(:ok)
    end
  end

  it "forces re-login after 24 hours since login even with continuous activity" do
    sign_in_and_pass_totp!

    25.times { travel 1.hour; get "/momentum" }
    expect(response).to redirect_to(login_path)
  end

  it "never forces re-login for the exempt email regardless of login age" do
    user = create(:user, status: :enabled, totp_enabled: true, totp_secret: AuthHelpers::DEFAULT_TOTP_SECRET,
                          email: ApplicationController::IDLE_TIMEOUT_EXEMPT_EMAIL)
    sign_in_and_pass_totp!(user: user)

    travel 3.days
    get "/momentum"
    expect(response).to have_http_status(:ok)
  end
end
