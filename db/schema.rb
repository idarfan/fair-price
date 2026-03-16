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

ActiveRecord::Schema[8.1].define(version: 2026_03_16_105726) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "flight_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_flight_conversations_on_token", unique: true
  end

  create_table "flight_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "flight_conversation_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["flight_conversation_id", "created_at"], name: "index_flight_messages_on_flight_conversation_id_and_created_at"
    t.index ["flight_conversation_id"], name: "index_flight_messages_on_flight_conversation_id"
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

  create_table "watchlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_watchlist_items_on_position"
    t.index ["symbol"], name: "index_watchlist_items_on_symbol", unique: true
  end

  add_foreign_key "flight_messages", "flight_conversations"
  add_foreign_key "ownership_holders", "ownership_snapshots"
end
