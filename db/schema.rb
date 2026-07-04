# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_04_151000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "fetch_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_detail"
    t.string "fetch_type", null: false
    t.datetime "fetched_at", null: false
    t.string "status", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_fetch_logs_on_status"
    t.index ["symbol", "fetched_at"], name: "index_fetch_logs_on_symbol_and_fetched_at"
  end

  create_table "fundamentals", force: :cascade do |t|
    t.integer "analyst_hold"
    t.integer "analyst_moderate_buy"
    t.integer "analyst_sell"
    t.integer "analyst_strong_buy"
    t.decimal "annual_income_m", precision: 12, scale: 2
    t.decimal "annual_revenue_m", precision: 12, scale: 2
    t.decimal "beta_60m", precision: 6, scale: 4
    t.datetime "created_at", null: false
    t.decimal "dividend_annual", precision: 8, scale: 4
    t.decimal "dividend_yield", precision: 6, scale: 4
    t.string "earnings_time"
    t.decimal "ebit_m", precision: 12, scale: 2
    t.decimal "ebitda_m", precision: 12, scale: 2
    t.decimal "eps_estimate_current_qtr"
    t.decimal "eps_growth_est_yoy"
    t.decimal "eps_prior_year_estimate"
    t.decimal "eps_ttm", precision: 10, scale: 4
    t.decimal "expected_move_pct", precision: 8, scale: 4
    t.datetime "fetched_at", null: false
    t.decimal "hist_vol", precision: 8, scale: 4
    t.decimal "iv", precision: 8, scale: 4
    t.integer "iv_percentile"
    t.decimal "iv_rank", precision: 5, scale: 2
    t.bigint "market_cap_k"
    t.date "most_recent_earnings_date"
    t.decimal "most_recent_eps", precision: 10, scale: 4
    t.date "next_earnings_date"
    t.integer "open_interest"
    t.integer "options_avg_volume"
    t.integer "options_volume"
    t.decimal "pb_ratio", precision: 8, scale: 2
    t.decimal "pcf_ratio", precision: 8, scale: 2
    t.decimal "pe_ttm", precision: 8, scale: 2
    t.decimal "ps_ratio", precision: 8, scale: 2
    t.decimal "put_call_oi_ratio", precision: 6, scale: 4
    t.decimal "put_call_vol_ratio", precision: 6, scale: 4
    t.string "sector"
    t.bigint "shares_outstanding_k"
    t.date "snapshot_date", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "snapshot_date"], name: "index_fundamentals_on_symbol_and_snapshot_date", unique: true
  end

  create_table "iv_daily_snapshots", force: :cascade do |t|
    t.decimal "atm_iv", precision: 8, scale: 4
    t.decimal "atm_strike", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 10, scale: 2
    t.date "snapshot_date", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["ticker", "snapshot_date"], name: "index_iv_daily_snapshots_on_ticker_and_snapshot_date", unique: true
  end

  create_table "iv_queries", force: :cascade do |t|
    t.integer "available_days"
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 10, scale: 2
    t.string "data_quality"
    t.decimal "delta", precision: 6, scale: 4
    t.date "expiry_date"
    t.decimal "iv", precision: 8, scale: 4
    t.decimal "ivp_1y", precision: 6, scale: 2
    t.decimal "ivp_2y", precision: 6, scale: 2
    t.decimal "ivr_1y", precision: 6, scale: 2
    t.decimal "ivr_2y", precision: 6, scale: 2
    t.boolean "low_iv_signal"
    t.string "option_type"
    t.datetime "queried_at"
    t.decimal "strike", precision: 10, scale: 2
    t.string "ticker"
    t.datetime "updated_at", null: false
  end

  create_table "iv_watchlists", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "group_tag", default: "general"
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["group_tag"], name: "index_iv_watchlists_on_group_tag"
    t.index ["symbol"], name: "index_iv_watchlists_on_symbol", unique: true
  end

  create_table "leaps_option_chain_snapshots", force: :cascade do |t|
    t.decimal "ask", precision: 10, scale: 4
    t.decimal "bid", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.decimal "delta", precision: 8, scale: 6
    t.integer "dte"
    t.date "expiration_date", null: false
    t.decimal "extrinsic_value", precision: 10, scale: 4
    t.decimal "intrinsic_value", precision: 10, scale: 4
    t.decimal "itm_probability", precision: 8, scale: 6
    t.decimal "iv", precision: 8, scale: 6
    t.decimal "last_price", precision: 10, scale: 4
    t.integer "open_interest"
    t.string "option_type", null: false
    t.datetime "scraped_at", null: false
    t.decimal "strike", precision: 10, scale: 4, null: false
    t.string "symbol", null: false
    t.decimal "underlying_price", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.decimal "vega", precision: 10, scale: 6
    t.decimal "vol_oi_ratio", precision: 8, scale: 4
    t.integer "volume"
    t.index ["symbol", "expiration_date", "strike", "option_type"], name: "idx_leaps_chain_unique", unique: true
    t.index ["symbol", "scraped_at"], name: "idx_leaps_chain_symbol_scraped"
  end

  create_table "margin_positions", force: :cascade do |t|
    t.decimal "buy_price", precision: 15, scale: 4, null: false
    t.date "closed_on"
    t.datetime "created_at", null: false
    t.date "opened_on", null: false
    t.integer "position", default: 0, null: false
    t.decimal "sell_price", precision: 15, scale: 4
    t.decimal "shares", precision: 15, scale: 5, null: false
    t.string "status", default: "open", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "opened_on"], name: "index_margin_positions_on_status_and_opened_on"
    t.index ["status"], name: "index_margin_positions_on_status"
  end

  create_table "max_pain_contract_snapshots", force: :cascade do |t|
    t.jsonb "available_expirations", default: []
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.jsonb "max_pain_by_expiry", default: []
    t.date "snapshot_date", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "snapshot_date"], name: "index_max_pain_contract_snapshots_on_symbol_and_snapshot_date", unique: true
  end

  create_table "max_pain_snapshots", force: :cascade do |t|
    t.jsonb "call_oi", default: []
    t.jsonb "call_pain", default: []
    t.datetime "created_at", null: false
    t.integer "dte"
    t.string "expiration", null: false
    t.datetime "fetched_at", null: false
    t.jsonb "iv_combined", default: []
    t.decimal "last_price", precision: 10, scale: 2
    t.decimal "max_pain_strike", precision: 10, scale: 2
    t.jsonb "put_oi", default: []
    t.jsonb "put_pain", default: []
    t.date "snapshot_date", null: false
    t.jsonb "strikes", default: []
    t.string "strikes_filter", default: "show_all", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.string "volume_oi_filter", default: "open_interest", null: false
    t.index ["symbol", "snapshot_date", "expiration", "strikes_filter", "volume_oi_filter"], name: "idx_max_pain_snapshots_filter_unique", unique: true
  end

  create_table "option_snapshots", force: :cascade do |t|
    t.decimal "ask", precision: 10, scale: 4
    t.decimal "bid", precision: 10, scale: 4
    t.string "contract_symbol", null: false
    t.datetime "created_at", null: false
    t.date "expiration", null: false
    t.decimal "implied_volatility", precision: 8, scale: 6
    t.boolean "in_the_money", default: false, null: false
    t.decimal "last_price", precision: 10, scale: 4
    t.integer "open_interest"
    t.string "option_type", null: false
    t.datetime "snapped_at", null: false
    t.date "snapshot_date", null: false
    t.decimal "strike", precision: 10, scale: 4, null: false
    t.bigint "tracked_ticker_id", null: false
    t.decimal "underlying_price", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.integer "volume"
    t.index "tracked_ticker_id, date_trunc('hour'::text, snapped_at), contract_symbol", name: "idx_option_snapshots_hourly", unique: true
    t.index ["expiration"], name: "index_option_snapshots_on_expiration"
    t.index ["option_type", "strike"], name: "index_option_snapshots_on_option_type_and_strike"
    t.index ["snapshot_date"], name: "index_option_snapshots_on_snapshot_date"
    t.index ["tracked_ticker_id"], name: "index_option_snapshots_on_tracked_ticker_id"
    t.check_constraint "bid > 0::numeric OR ask > 0::numeric OR last_price > 0::numeric", name: "chk_option_has_market_quote"
  end

  create_table "options_flow_trades", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "delta", precision: 5, scale: 4
    t.integer "dte"
    t.timestamptz "expires_at"
    t.datetime "fetched_at", null: false
    t.boolean "is_cancelled", default: false, null: false
    t.boolean "is_multi_leg", default: false, null: false
    t.boolean "is_stock_combo", default: false, null: false
    t.decimal "iv", precision: 6, scale: 4
    t.boolean "large_premium", default: false, null: false
    t.boolean "likely_institutional", default: false, null: false
    t.boolean "low_liquidity_period", default: false, null: false
    t.string "open_close"
    t.integer "open_interest"
    t.string "option_type"
    t.bigint "premium"
    t.string "side"
    t.integer "size"
    t.date "snapshot_date", null: false
    t.decimal "strike", precision: 10, scale: 2
    t.string "symbol", null: false
    t.boolean "timing_anomaly", default: false, null: false
    t.string "trade_condition"
    t.decimal "trade_price", precision: 8, scale: 4
    t.string "trade_time"
    t.datetime "updated_at", null: false
    t.boolean "urgency_high", default: false, null: false
    t.integer "volume"
    t.index ["symbol", "snapshot_date", "is_cancelled", "is_multi_leg"], name: "idx_oft_directional"
    t.index ["symbol", "snapshot_date"], name: "index_options_flow_trades_on_symbol_and_snapshot_date"
  end

  create_table "options_flows", force: :cascade do |t|
    t.bigint "ask_call_premium"
    t.decimal "ask_call_put_ratio"
    t.bigint "ask_put_premium"
    t.bigint "bearish_delta"
    t.bigint "bearish_sentiment"
    t.bigint "bullish_delta"
    t.bigint "bullish_sentiment"
    t.bigint "call_premium_total"
    t.decimal "call_put_ratio"
    t.datetime "created_at", null: false
    t.bigint "delta_imbalance"
    t.datetime "fetched_at", null: false
    t.integer "high_delta_call_count"
    t.integer "large_call_count"
    t.integer "large_put_count"
    t.bigint "long_dte_call_premium"
    t.bigint "net_sentiment"
    t.bigint "put_premium_total"
    t.bigint "short_dte_put_premium"
    t.date "snapshot_date", null: false
    t.integer "sweep_block_count"
    t.string "symbol", null: false
    t.jsonb "top_large_orders"
    t.integer "total_trades_loaded"
    t.datetime "updated_at", null: false
    t.index ["symbol", "snapshot_date"], name: "index_options_flows_on_symbol_and_snapshot_date", unique: true
  end

  create_table "options_snapshots", force: :cascade do |t|
    t.datetime "cached_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 10, scale: 4
    t.string "expiration_date"
    t.decimal "iv_rank", precision: 5, scale: 2
    t.decimal "iv_skew", precision: 6, scale: 4
    t.decimal "pc_ratio", precision: 6, scale: 4
    t.jsonb "raw_data", default: {}, null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["cached_at"], name: "index_options_snapshots_on_cached_at"
    t.index ["symbol", "expiration_date"], name: "index_options_snapshots_on_symbol_expiration"
    t.index ["symbol"], name: "index_options_snapshots_on_symbol"
  end

  create_table "ownership_holders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "filing_date"
    t.bigint "market_value"
    t.string "name", null: false
    t.bigint "ownership_snapshot_id", null: false
    t.decimal "pct", precision: 8, scale: 4
    t.decimal "pct_change", precision: 8, scale: 4
    t.datetime "updated_at", null: false
    t.index ["ownership_snapshot_id", "name"], name: "index_ownership_holders_on_ownership_snapshot_id_and_name", unique: true
    t.index ["ownership_snapshot_id"], name: "index_ownership_holders_on_ownership_snapshot_id"
  end

  create_table "ownership_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "insider_pct", precision: 6, scale: 2
    t.integer "institution_count"
    t.decimal "institutional_pct", precision: 6, scale: 2
    t.string "quarter", null: false
    t.date "snapshot_date", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["ticker", "quarter"], name: "index_ownership_snapshots_on_ticker_and_quarter", unique: true
    t.index ["ticker", "snapshot_date"], name: "index_ownership_snapshots_on_ticker_and_snapshot_date"
  end

  create_table "portfolios", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.decimal "sell_price", precision: 15, scale: 2
    t.decimal "shares", precision: 15, scale: 5, null: false
    t.string "symbol", null: false
    t.decimal "unit_cost", precision: 15, scale: 5, null: false
    t.datetime "updated_at", null: false
    t.index ["symbol"], name: "index_portfolios_on_symbol"
  end

  create_table "price_alerts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "condition", default: "above", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "symbol", null: false
    t.decimal "target_price", precision: 12, scale: 4
    t.datetime "triggered_at"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_price_alerts_on_active"
    t.index ["position"], name: "index_price_alerts_on_position"
    t.index ["symbol"], name: "index_price_alerts_on_symbol"
  end

  create_table "skew_rank_daily", force: :cascade do |t|
    t.decimal "call_iv_025", precision: 8, scale: 6
    t.datetime "created_at", null: false
    t.decimal "put_iv_025", precision: 8, scale: 6
    t.decimal "skew_pts", precision: 6, scale: 2
    t.decimal "skew_rank", precision: 5, scale: 2
    t.date "snapshot_date", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["ticker", "snapshot_date"], name: "index_skew_rank_daily_on_ticker_and_snapshot_date", unique: true
  end

  create_table "skew_rank_intradays", force: :cascade do |t|
    t.decimal "call_iv_025", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 10, scale: 2
    t.decimal "put_iv_025", precision: 10, scale: 6
    t.decimal "skew_pts", precision: 8, scale: 4
    t.datetime "snapshot_time", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["snapshot_time"], name: "index_skew_rank_intradays_on_snapshot_time"
    t.index ["ticker", "snapshot_time"], name: "index_skew_rank_intradays_on_ticker_and_snapshot_time", unique: true
  end

  create_table "strike_chain_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "scraped_at", null: false
    t.decimal "spot_price", precision: 10, scale: 4
    t.jsonb "strikes", default: [], null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol"], name: "index_strike_chain_snapshots_on_symbol", unique: true
  end

  create_table "technical_analyses", force: :cascade do |t|
    t.decimal "adr_100d", precision: 10, scale: 4
    t.decimal "adr_14d", precision: 10, scale: 4
    t.decimal "adr_20d", precision: 10, scale: 4
    t.decimal "adr_50d", precision: 10, scale: 4
    t.decimal "adr_9d", precision: 10, scale: 4
    t.decimal "adr_pct_100d", precision: 8, scale: 4
    t.decimal "adr_pct_14d", precision: 8, scale: 4
    t.decimal "adr_pct_20d", precision: 8, scale: 4
    t.decimal "adr_pct_50d", precision: 8, scale: 4
    t.decimal "adr_pct_9d", precision: 8, scale: 4
    t.decimal "adx_100d", precision: 8, scale: 4
    t.decimal "adx_14d", precision: 8, scale: 4
    t.decimal "adx_20d", precision: 8, scale: 4
    t.decimal "adx_50d", precision: 8, scale: 4
    t.decimal "adx_9d", precision: 8, scale: 4
    t.decimal "atr_100d", precision: 10, scale: 4
    t.decimal "atr_14d", precision: 10, scale: 4
    t.decimal "atr_20d", precision: 10, scale: 4
    t.decimal "atr_50d", precision: 10, scale: 4
    t.decimal "atr_9d", precision: 10, scale: 4
    t.decimal "atr_pct_100d", precision: 8, scale: 4
    t.decimal "atr_pct_14d", precision: 8, scale: 4
    t.decimal "atr_pct_20d", precision: 8, scale: 4
    t.decimal "atr_pct_50d", precision: 8, scale: 4
    t.decimal "atr_pct_9d", precision: 8, scale: 4
    t.datetime "created_at", null: false
    t.decimal "di_minus_100d", precision: 8, scale: 4
    t.decimal "di_minus_14d", precision: 8, scale: 4
    t.decimal "di_minus_20d", precision: 8, scale: 4
    t.decimal "di_minus_50d", precision: 8, scale: 4
    t.decimal "di_minus_9d", precision: 8, scale: 4
    t.decimal "di_plus_100d", precision: 8, scale: 4
    t.decimal "di_plus_14d", precision: 8, scale: 4
    t.decimal "di_plus_20d", precision: 8, scale: 4
    t.decimal "di_plus_50d", precision: 8, scale: 4
    t.decimal "di_plus_9d", precision: 8, scale: 4
    t.datetime "fetched_at", null: false
    t.decimal "hist_vol_100d", precision: 8, scale: 4
    t.decimal "hist_vol_14d", precision: 8, scale: 4
    t.decimal "hist_vol_20d", precision: 8, scale: 4
    t.decimal "hist_vol_50d", precision: 8, scale: 4
    t.decimal "hist_vol_9d", precision: 8, scale: 4
    t.decimal "ma_100d", precision: 10, scale: 2
    t.decimal "ma_200d", precision: 10, scale: 2
    t.decimal "ma_20d", precision: 10, scale: 2
    t.decimal "ma_50d", precision: 10, scale: 2
    t.decimal "ma_5d", precision: 10, scale: 2
    t.bigint "ma_avg_vol_100d"
    t.bigint "ma_avg_vol_200d"
    t.bigint "ma_avg_vol_20d"
    t.bigint "ma_avg_vol_50d"
    t.bigint "ma_avg_vol_5d"
    t.bigint "ma_avg_vol_ytd"
    t.decimal "ma_pct_chg_100d", precision: 8, scale: 4
    t.decimal "ma_pct_chg_200d", precision: 8, scale: 4
    t.decimal "ma_pct_chg_20d", precision: 8, scale: 4
    t.decimal "ma_pct_chg_50d", precision: 8, scale: 4
    t.decimal "ma_pct_chg_5d", precision: 8, scale: 4
    t.decimal "ma_pct_chg_ytd", precision: 8, scale: 4
    t.decimal "ma_price_chg_100d", precision: 10, scale: 2
    t.decimal "ma_price_chg_200d", precision: 10, scale: 2
    t.decimal "ma_price_chg_20d", precision: 10, scale: 2
    t.decimal "ma_price_chg_50d", precision: 10, scale: 2
    t.decimal "ma_price_chg_5d", precision: 10, scale: 2
    t.decimal "ma_price_chg_ytd", precision: 10, scale: 2
    t.decimal "ma_ytd", precision: 10, scale: 2
    t.date "snapshot_date", null: false
    t.decimal "stoch_d_100d", precision: 8, scale: 4
    t.decimal "stoch_d_14d", precision: 8, scale: 4
    t.decimal "stoch_d_20d", precision: 8, scale: 4
    t.decimal "stoch_d_50d", precision: 8, scale: 4
    t.decimal "stoch_d_9d", precision: 8, scale: 4
    t.decimal "stoch_k_100d", precision: 8, scale: 4
    t.decimal "stoch_k_14d", precision: 8, scale: 4
    t.decimal "stoch_k_20d", precision: 8, scale: 4
    t.decimal "stoch_k_50d", precision: 8, scale: 4
    t.decimal "stoch_k_9d", precision: 8, scale: 4
    t.decimal "stoch_raw_100d", precision: 8, scale: 4
    t.decimal "stoch_raw_14d", precision: 8, scale: 4
    t.decimal "stoch_raw_20d", precision: 8, scale: 4
    t.decimal "stoch_raw_50d", precision: 8, scale: 4
    t.decimal "stoch_raw_9d", precision: 8, scale: 4
    t.decimal "stoch_rs_100d", precision: 8, scale: 4
    t.decimal "stoch_rs_14d", precision: 8, scale: 4
    t.decimal "stoch_rs_20d", precision: 8, scale: 4
    t.decimal "stoch_rs_50d", precision: 8, scale: 4
    t.decimal "stoch_rs_9d", precision: 8, scale: 4
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["symbol", "snapshot_date"], name: "index_technical_analyses_on_symbol_and_snapshot_date", unique: true
  end

  create_table "tracked_tickers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_tracked_tickers_on_active"
    t.index ["symbol"], name: "index_tracked_tickers_on_symbol", unique: true
  end

  create_table "watched_tickers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "added_at", null: false
    t.datetime "created_at", null: false
    t.datetime "last_fetched_at"
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["ticker"], name: "index_watched_tickers_on_ticker", unique: true
  end

  create_table "watchlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_watchlist_items_on_position"
    t.index ["symbol"], name: "index_watchlist_items_on_symbol", unique: true
  end

  add_foreign_key "option_snapshots", "tracked_tickers"
  add_foreign_key "ownership_holders", "ownership_snapshots"
end
