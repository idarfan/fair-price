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
      resources :margin_positions, only: [ :index, :create, :update, :destroy ] do
        collection { get :price_lookup }
        member      { post :close }
      end
    end
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

  # Ownership Structure
  get  "ownership",         to: "ownership#index",   as: :ownership
  get  "ownership/history", to: "ownership#history", as: :ownership_history
  post "ownership/fetch",   to: "ownership#fetch",   as: :ownership_fetch

  # Lookbook component previews (development only)
  mount Lookbook::Engine, at: "/lookbook" if defined?(Lookbook)
end
