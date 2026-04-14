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

ActiveRecord::Schema[8.1].define(version: 2026_04_14_042936) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
