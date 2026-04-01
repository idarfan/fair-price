# frozen_string_literal: true

Rails.application.routes.draw do
  # JSON API (for external/programmatic access)
  namespace :api do
    namespace :v1 do
      get "valuations/:ticker", to: "valuations#show",
          constraints: { ticker: /[A-Za-z0-9.\-]{1,10}/ }

      get  "ownership_snapshots/:ticker", to: "ownership_snapshots#index",  as: :ownership_snapshots
      post "ownership_snapshots/:ticker", to: "ownership_snapshots#create"

      # Options Analyzer API
      get  "options/:symbol/chain",      to: "options#chain",
           constraints: { symbol: /[A-Za-z0-9.\-]{1,10}/ }
      get  "options/:symbol/sentiment",  to: "options#sentiment",
           constraints: { symbol: /[A-Za-z0-9.\-]{1,10}/ }
      get  "options/:symbol/iv_rank",    to: "options#iv_rank",
           constraints: { symbol: /[A-Za-z0-9.\-]{1,10}/ }
      post "options/strategy_recommend", to: "options#strategy_recommend"
      post "options/analyze_image",      to: "options#analyze_image"

      # Technical chart data (price, volume, MA, RSI)
      get "charts/:symbol", to: "charts#show",
          constraints: { symbol: /[A-Za-z0-9.\-]{1,10}/ }
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # HTML app
  get "valuations/:ticker", to: "valuations#show", as: :valuation,
      constraints: { ticker: /[A-Za-z0-9.\-]{1,10}/ }
  root "valuations#index"

  # Watchlist / Price Alerts
  get    "watchlist",                          to: "stock_alerts#index",            as: :watchlist
  post   "watchlist",                          to: "stock_alerts#create"
  get    "watchlist/new",                      to: "stock_alerts#new",              as: :new_watchlist_alert
  patch  "watchlist/reorder",                  to: "stock_alerts#reorder",          as: :reorder_watchlist
  get    "watchlist/:id/edit",                 to: "stock_alerts#edit",             as: :edit_watchlist_alert
  patch  "watchlist/:id",                      to: "stock_alerts#update",           as: :watchlist_alert
  delete "watchlist/:id",                      to: "stock_alerts#destroy"
  patch  "watchlist/:id/toggle",               to: "stock_alerts#toggle"
  patch  "watchlist/:id/toggle_condition",     to: "stock_alerts#toggle_condition"

  # Portfolio
  get   "portfolio",                to: "portfolios#index",      as: :portfolio_index
  post  "portfolio",                to: "portfolios#create"
  post  "portfolio/ocr_import",     to: "portfolios#ocr_import", as: :ocr_import_portfolio
  patch "portfolio/reorder",        to: "portfolios#reorder",    as: :reorder_portfolio
  get   "portfolio/quotes",         to: "portfolios#quotes",     as: :portfolio_quotes
  get   "portfolio/ownership",      to: "portfolios#ownership",  as: :portfolio_ownership
  patch "portfolio/:id",            to: "portfolios#update",     as: :portfolio_holding
  delete "portfolio/:id",           to: "portfolios#destroy"

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
      constraints: { symbol: /[A-Za-z0-9.\-]{1,10}/ }

  # Ownership Structure
  get  "ownership",         to: "ownership#index",   as: :ownership
  get  "ownership/history", to: "ownership#history", as: :ownership_history
  post "ownership/fetch",   to: "ownership#fetch",   as: :ownership_fetch

  # Lookbook component previews (development only)
  mount Lookbook::Engine, at: "/lookbook" if defined?(Lookbook)
end
