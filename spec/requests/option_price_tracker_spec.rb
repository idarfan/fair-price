# frozen_string_literal: true

require "rails_helper"

# tracked_tickers 是**共用**的蒐集設定，不是個人清單——option_snapshots 綁的是
# tracked_ticker_id 而非 symbol（81 萬列），沒辦法像觀察清單那樣分給每個使用者。
# 折衷是「所有人可讀、只有 admin 能改」（Api::V1::TrackedTickersController）。
#
# 這支釘住的是**前端拿到的旗標**：後端閘門本身由 watchlist_isolation_spec 覆蓋，
# 這裡確保 UI 不會對非 admin 顯示按不動的按鈕（按下去只回一句「新增失敗」，
# 看起來像功能壞掉而不是權限限制）。
RSpec.describe "Option Price Tracker 頁面", type: :request do
  it "非 admin 拿到 can-manage=false" do
    get "/option_price_tracker"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-can-manage="false"')
  end

  it "admin 拿到 can-manage=true" do
    admin = create(:user, status: :enabled, admin: true, totp_enabled: true,
                          totp_secret: AuthHelpers::DEFAULT_TOTP_SECRET)
    sign_in_and_pass_totp!(user: admin)

    get "/option_price_tracker"

    expect(response.body).to include('data-can-manage="true"')
  end

  it "追蹤清單本身所有人都讀得到（共用蒐集設定）" do
    create(:tracked_ticker, symbol: "SHARED")

    get "/option_price_tracker"

    expect(response.body).to include("SHARED")
  end
end
