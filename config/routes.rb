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
        member { post :collect }
      end
      get "option_snapshots/:symbol",               to: "option_snapshots#index",
          constraints: { symbol: TICKER_CONSTRAINT }
      get "option_snapshots/:symbol/premium_trend", to: "option_snapshots#premium_trend",
          constraints: { symbol: TICKER_CONSTRAINT }

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

  # HTML app
  get "valuations/:ticker", to: "valuations#show", as: :valuation,
      constraints: { ticker: TICKER_CONSTRAINT }
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
  get  "technical_dashboard/status",  to: "technical_dashboards#status",  as: :technical_dashboard_status

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
