# frozen_string_literal: true

require "rails_helper"

# 稽核 C-2 第二階段迴歸：觀察清單過去是全站共用的，5 個已核准帳號彼此可讀可改可刪。
RSpec.describe "觀察清單的跨使用者隔離", type: :request do
  describe "Daily Momentum 觀察清單" do
    it "看不到別人的項目" do
      create(:watchlist_item, symbol: "OTHER", user: create(:user))
      create(:watchlist_item, symbol: "MINE",  user: signed_in_user)

      get momentum_report_path

      expect(response.body).to include("MINE")
      expect(response.body).not_to include("OTHER")
    end

    it "知道 id 也刪不掉別人的項目" do
      foreign = create(:watchlist_item, user: create(:user))

      expect { delete momentum_watchlist_item_path(foreign) }.not_to change(WatchlistItem, :count)
    end
  end

  describe "IV Skew 追蹤清單" do
    it "看不到別人的項目" do
      create(:iv_watchlist, symbol: "OTHER", user: create(:user))
      create(:iv_watchlist, symbol: "MINE",  user: signed_in_user)

      get iv_watchlists_path

      expect(response.body).to include("MINE")
      expect(response.body).not_to include("OTHER")
    end

    it "知道 id 也刪不掉別人的項目" do
      foreign = create(:iv_watchlist, user: create(:user))

      expect { delete iv_watchlist_path(foreign) }.not_to change(IvWatchlist, :count)
    end
  end

  # 排程作業（ouou-pre-market、iv-skew-snapshot）沒有 current_user，
  # 必須拿到所有使用者的聯集，否則加了歸屬之後別人的代號就不會被蒐集。
  describe "排程取得的是所有使用者的聯集" do
    it "OuouPreMarketService 涵蓋每個使用者的代號" do
      create(:watchlist_item, symbol: "AAAA", user: create(:user))
      create(:watchlist_item, symbol: "BBBB", user: create(:user))

      symbols = OuouPreMarketService.new.send(:watchlist_symbols)

      expect(symbols).to include("AAAA", "BBBB")
    end

    it "IvWatchlist 的排程查詢涵蓋每個使用者的代號" do
      create(:iv_watchlist, symbol: "CCCC", user: create(:user))
      create(:iv_watchlist, symbol: "DDDD", user: create(:user))

      expect(IvWatchlist.active.pluck(:symbol).uniq).to include("CCCC", "DDDD")
    end
  end

  describe "tracked_tickers（共用蒐集設定）" do
    let(:admin_user) do
      create(:user, status: :enabled, admin: true, totp_enabled: true,
                    totp_secret: AuthHelpers::DEFAULT_TOTP_SECRET)
    end

    it "非 admin 不能刪除，避免連帶砍掉歷史快照" do
      ticker = create(:tracked_ticker)

      expect { delete "/api/v1/tracked_tickers/#{ticker.id}" }.not_to change(TrackedTicker, :count)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("admin_required")
    end

    it "非 admin 仍然讀得到清單" do
      create(:tracked_ticker, symbol: "SHARED")

      get "/api/v1/tracked_tickers"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |t| t["symbol"] }).to include("SHARED")
    end

    it "admin 可以刪除" do
      sign_in_and_pass_totp!(user: admin_user)
      ticker = create(:tracked_ticker)

      expect { delete "/api/v1/tracked_tickers/#{ticker.id}" }.to change(TrackedTicker, :count).by(-1)
    end

    # require_admin! 的 only: 清單有四個 action。原本只測 destroy——
    # 把 create 從清單裡拿掉不會有任何測試失敗，那道閘門等於沒被釘住。
    it "非 admin 不能新增" do
      expect { post "/api/v1/tracked_tickers", params: { symbol: "NEWSYM" } }
        .not_to change(TrackedTicker, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("admin_required")
    end

    it "非 admin 不能修改（例如停用別人在用的代號）" do
      ticker = create(:tracked_ticker, active: true)

      patch "/api/v1/tracked_tickers/#{ticker.id}",
            params: { tracked_ticker: { active: false } }

      expect(response).to have_http_status(:forbidden)
      expect(ticker.reload.active).to be(true)
    end

    it "非 admin 不能觸發蒐集（會花掉爬蟲配額）" do
      ticker = create(:tracked_ticker)

      expect { post "/api/v1/tracked_tickers/#{ticker.id}/collect" }
        .not_to have_enqueued_job(CollectOptionSnapshotsJob)

      expect(response).to have_http_status(:forbidden)
    end

    it "admin 可以新增" do
      sign_in_and_pass_totp!(user: admin_user)

      expect { post "/api/v1/tracked_tickers", params: { symbol: "NEWSYM" } }
        .to change(TrackedTicker, :count).by(1)

      expect(response).to have_http_status(:created)
    end
  end
end
