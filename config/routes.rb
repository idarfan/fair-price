# frozen_string_literal: true

TICKER_CONSTRAINT = /[A-Za-z0-9.\-]{1,10}/

Rails.application.routes.draw do
  # JSON API (for external/programmatic access)
  namespace :api do
    namespace :v1 do
      get "valuations/:ticker", to: "valuations#show",
          constraints: { ticker: TICKER_CONSTRAINT }

      get  "ownership_snapshots/:ticker", to: "ownership_snapshots#index",  as: :ownership_snapshots
      post "ownership_snapshots/:ticker", to: "ownership_snapshots#create"

      # Options Analyzer API
      get  "options/:symbol/chain",      to: "options#chain",
           constraints: { symbol: TICKER_CONSTRAINT }
      get  "options/:symbol/sentiment",  to: "options#sentiment",
           constraints: { symbol: TICKER_CONSTRAINT }
      get  "options/:symbol/iv_rank",    to: "options#iv_rank",
           constraints: { symbol: TICKER_CONSTRAINT }
      post "options/strategy_recommend", to: "options#strategy_recommend"
      post "options/analyze_image",      to: "options#analyze_image"

      # Technical chart data (price, volume, MA, RSI)
      get "charts/:symbol", to: "charts#show",
          constraints: { symbol: TICKER_CONSTRAINT }

      # Option Price History Tracker
      resources :tracked_tickers, only: [ :index, :create, :update, :destroy ] do
        member     { post :collect }
        collection { get  :collect_status }
      end
      get "option_snapshots/:symbol",               to: "option_snapshots#index",
          constraints: { symbol: TICKER_CONSTRAINT }
      get "option_snapshots/:symbol/premium_trend", to: "option_snapshots#premium_trend",
          constraints: { symbol: TICKER_CONSTRAINT }

      # LEAPS 排行表欄位順序（全站設定，只有 admin 能寫）
      put "leaps/column_order", to: "leaps_column_orders#update", as: :leaps_column_order

      # Margin Trade Calculator
      get "iv_skew/:ticker/history", to: "iv_skew#history",
          constraints: { ticker: TICKER_CONSTRAINT }

            resources :margin_positions, only: [ :index, :create, :update, :destroy ] do
        collection { get :price_lookup }
        member      { post :close }
      end
    end

    # IV Analysis API
    get    "iv_analysis/expirations",          to: "iv_analysis#expirations"
    post   "iv_analysis",                    to: "iv_analysis#create"
    get    "iv_analysis/watchlist",          to: "iv_analysis#watchlist"
    delete "iv_analysis/watchlist/:ticker",  to: "iv_analysis#watchlist_destroy",
           constraints: { ticker: TICKER_CONSTRAINT }
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  get    "login",                       to: "sessions#new"
  get    "auth/google_oauth2/callback", to: "sessions#google_callback"
  get    "auth/failure",                to: "sessions#failure"
  delete "logout",                      to: "sessions#destroy"
  get    "account_disabled",            to: "sessions#account_disabled"
  get    "pending_approval",            to: "sessions#pending_approval"

  get  "two_factor/setup",        to: "two_factor#setup"
  post "two_factor/setup",        to: "two_factor#create_setup"
  get  "two_factor/challenge",    to: "two_factor#challenge"
  post "two_factor/challenge",    to: "two_factor#create_challenge"
  get  "two_factor/backup_codes", to: "two_factor#backup_codes"

  get  "settings/security",              to: "account_security#show"
  post "settings/security/backup_codes", to: "account_security#regenerate_backup_codes"
  post "settings/security/logout_all",   to: "account_security#logout_all_devices"

  namespace :admin do
    get   "users",               to: "users#index"
    get   "users/:id",           to: "users#show"
    patch "users/:id/approve",    to: "users#approve"
    patch "users/:id/disable",    to: "users#disable"
    patch "users/:id/reactivate", to: "users#reactivate"
  end

  post "track/page_view", to: "track#page_view"
  post "track/command",   to: "track#command"

  # HTML app
  #
  # 這裡刻意不用 TICKER_CONSTRAINT：搜尋列（tickerSearch.ts）只檢查非空就直接導頁，
  # 嚴格的路由 constraint 會讓「台積電」「AAPL X」這類輸入直接吃到原始 404 頁，
  # 而 ValuationsController#validate_ticker 那段友善提示因為永遠進不來而形同虛設。
  # 改成收下整個 segment、由 controller 驗證並導回首頁顯示「無效的股票代號」。
  # format: false 是必要的——放寬 constraint 之後，Rails 會把 BRK.B 的 .B 當成
  # 格式後綴切掉（原本的 constraint 因為含 `.` 才剛好沒發生）。
  # API 端（api/v1/valuations）維持嚴格 constraint：對 API 而言 404 才是對的回應。
  get "valuations/:ticker", to: "valuations#show", as: :valuation,
      constraints: { ticker: %r{[^/]{1,64}} }, format: false
  root "valuations#index"

  # Watchlist / Price Alerts
  resources :watchlist_alerts, path: :watchlist, controller: :stock_alerts, except: [ :show ] do
    collection { patch :reorder }
    member do
      patch :toggle
      patch :toggle_condition
    end
  end

  # Portfolio
  resources :portfolios, path: :portfolio, except: [ :new, :edit, :show ] do
    collection do
      post  :ocr_import
      patch :reorder
      get   :quotes
      get   :ownership
    end
  end

  # Daily Momentum
  get   "momentum",                       to: "reports#index",              as: :momentum_report
  get   "momentum/news",                  to: "reports#company_news",       as: :momentum_company_news
  get   "momentum/analysis",              to: "reports#analysis",           as: :momentum_analysis
  post  "momentum/render_markdown",       to: "reports#render_markdown",    as: :momentum_render_markdown
  post  "momentum/watchlist",             to: "watchlist_items#create",     as: :momentum_watchlist_items
  patch "momentum/watchlist/reorder",     to: "watchlist_items#reorder",    as: :reorder_momentum_watchlist
  patch "momentum/watchlist/:id",         to: "watchlist_items#update",     as: :momentum_watchlist_item
  delete "momentum/watchlist/:id",        to: "watchlist_items#destroy"

  # Options Analyzer
  get "options",         to: "options#index", as: :options
  get "options/:symbol", to: "options#show",  as: :option_detail,
      constraints: { symbol: TICKER_CONSTRAINT }

  # Margin Trade Calculator
  get "margin", to: "margin#index", as: :margin

  # Option Price History Tracker
  get "option_price_tracker", to: "option_price_tracker#index", as: :option_price_tracker

  # Option Profit Calculator
  get "option_profit_calc", to: "option_profit_calc#index", as: :option_profit_calc

  # Ownership Structure
  get  "ownership",         to: "ownership#index",   as: :ownership
  get  "ownership/history", to: "ownership#history", as: :ownership_history
  post "ownership/fetch",   to: "ownership#fetch",   as: :ownership_fetch

  # IV Analysis
  get "iv_analysis", to: "iv_analysis#index", as: :iv_analysis

  # Technical / Fundamental / Options Flow Dashboard
  get  "technical_dashboard",         to: "technical_dashboards#index",   as: :technical_dashboard
  post "technical_dashboard/analyze", to: "technical_dashboards#analyze", as: :technical_dashboard_analyze
  get  "technical_dashboard/status",       to: "technical_dashboards#status",       as: :technical_dashboard_status
  post "technical_dashboard/fetch_max_pain", to: "technical_dashboards#fetch_max_pain", as: :technical_dashboard_fetch_max_pain

  # LEAPS Call 候選排行
  get  "leaps",         to: "leaps_recommendations#index",   as: :leaps_recommendations
  post "leaps/analyze", to: "leaps_recommendations#analyze", as: :leaps_recommendations_analyze
  get  "leaps/status",  to: "leaps_recommendations#status",  as: :leaps_recommendations_status

  # Bull Put Spread 三級試算工具
  get  "bpus",                    to: "bull_put_spreads#index",             as: :bull_put_spreads
  post "bpus/fetch_expirations",  to: "bull_put_spreads#fetch_expirations", as: :bull_put_spreads_fetch_expirations
  post "bpus/fetch_chain",        to: "bull_put_spreads#fetch_chain",       as: :bull_put_spreads_fetch_chain
  get  "bpus/status",             to: "bull_put_spreads#status",            as: :bull_put_spreads_status
  post "bpus/calculate",          to: "bull_put_spreads#calculate",         as: :bull_put_spreads_calculate
  get  "bpus/volatility",         to: "bull_put_spreads#volatility",        as: :bull_put_spreads_volatility

  # 牛市看漲價差（Bull Call Vertical Spread）試算工具
  get  "bcvs",                   to: "bull_call_spreads#index",             as: :bull_call_spreads
  post "bcvs/fetch_expirations", to: "bull_call_spreads#fetch_expirations", as: :bull_call_spreads_fetch_expirations
  post "bcvs/fetch_chain",       to: "bull_call_spreads#fetch_chain",       as: :bull_call_spreads_fetch_chain
  get  "bcvs/status",            to: "bull_call_spreads#status",            as: :bull_call_spreads_status
  post "bcvs/recommend",         to: "bull_call_spreads#recommend",         as: :bull_call_spreads_recommend
  post "bcvs/calculate",         to: "bull_call_spreads#calculate",         as: :bull_call_spreads_calculate

  # 期權小學堂（原 public/csp/ 靜態檔案，改走 controller 以套用登入驗證與瀏覽記錄）
  get "csp",       to: redirect("/csp/index.html")
  get "csp/*path", to: "csp_lessons#show", as: :csp_lesson, format: false, constraints: { path: /.*/ }

# IV Skew Watchlist
resources :iv_watchlists, only: [ :index, :create, :destroy ] do
  member do
    patch :toggle
  end
  collection do
    get "chart_data/:symbol", to: "iv_watchlists#chart_data", as: :iv_watchlist_chart_data
  end
end

  # Lookbook component previews (development only)

  mount Lookbook::Engine, at: "/lookbook" if defined?(Lookbook)
end
