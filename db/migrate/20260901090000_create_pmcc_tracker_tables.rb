# frozen_string_literal: true

# pmcc-tracker Phase 1：部位追蹤與損益帳本的資料模型。
#
# user_id 由同日的 20260901093000_add_user_to_pmcc_positions 補上——
# 當初決定不加，後來確認真正的風險是「被別人寫入」而非「被別人看到」，
# 見該 migration 的註解。
#
# 精度沿用既有慣例，不另造：價格 decimal(10,4)（同 pmcc_short_call_snapshots）、
# 金額 decimal(15,4)（同 margin_positions.buy_price）。
class CreatePmccTrackerTables < ActiveRecord::Migration[8.1]
  def change
    create_table :pmcc_positions do |t|
      t.string  :ticker,           null: false
      t.integer :long_contracts,   null: false, default: 1
      t.decimal :long_strike,      null: false, precision: 10, scale: 4
      t.date    :long_expiration,  null: false
      t.decimal :long_entry_cost,  null: false, precision: 10, scale: 4
      t.date    :long_entry_date,  null: false
      t.string  :status,           null: false, default: "active"
      t.datetime :closed_at

      t.timestamps
    end
    add_index :pmcc_positions, [ :ticker, :status ]
    add_check_constraint :pmcc_positions, "long_contracts > 0",   name: "pmcc_positions_contracts_positive"
    add_check_constraint :pmcc_positions, "long_strike > 0",      name: "pmcc_positions_strike_positive"
    add_check_constraint :pmcc_positions, "long_entry_cost > 0",  name: "pmcc_positions_entry_cost_positive"

    create_table :pmcc_short_legs do |t|
      t.references :pmcc_position,   null: false, foreign_key: true
      t.integer :contracts,          null: false, default: 1
      t.decimal :short_strike,       null: false, precision: 10, scale: 4
      t.date    :short_expiration,   null: false
      t.decimal :premium_collected,  null: false, precision: 10, scale: 4
      t.datetime :opened_at,         null: false
      t.string  :status,             null: false, default: "open"
      t.decimal :close_cost,         precision: 10, scale: 4
      t.datetime :closed_at
      # roll 鏈：指向「這一腳滾去哪一腳」。self-reference 不能用 foreign_key: true
      # 的簡寫（Rails 會去找 rolled_tos 表），要明寫 to_table。
      t.references :rolled_to, foreign_key: { to_table: :pmcc_short_legs }

      t.timestamps
    end
    add_index :pmcc_short_legs, [ :pmcc_position_id, :status ]
    add_check_constraint :pmcc_short_legs, "contracts > 0",         name: "pmcc_short_legs_contracts_positive"
    add_check_constraint :pmcc_short_legs, "short_strike > 0",      name: "pmcc_short_legs_strike_positive"
    add_check_constraint :pmcc_short_legs, "close_cost IS NULL OR close_cost >= 0",
                         name: "pmcc_short_legs_close_cost_non_negative"

    create_table :pmcc_pnl_events do |t|
      t.references :pmcc_position, null: false, foreign_key: true
      t.string  :event_type,       null: false
      # 已扣手續費後的真實現金流。**不得寫入任何估算值**——已實現帳本的價值
      # 在於可稽核，混進估算就跟券商對帳單永遠對不起來（見 Phase 4）。
      t.decimal :realized_pnl,     null: false, precision: 15, scale: 4
      t.decimal :fees,             null: false, default: 0, precision: 15, scale: 4
      # 建立事件當下實際用到的報價。pmcc_leg_quotes 是覆蓋式快照，
      # 事後回查已經被蓋掉，要能回溯就必須在這裡留存。
      t.jsonb   :quote_snapshot
      t.datetime :occurred_at,     null: false
      t.text :note

      t.timestamps
    end
    add_index :pmcc_pnl_events, [ :pmcc_position_id, :occurred_at ]
    add_check_constraint :pmcc_pnl_events, "fees >= 0", name: "pmcc_pnl_events_fees_non_negative"

    # Phase 0 的落點：被追蹤的腳（目前只有長腳）的最新報價。
    # 不沿用 pmcc_short_call_snapshots——長腳不是 short call，表名語意不符。
    create_table :pmcc_leg_quotes do |t|
      t.string  :symbol,          null: false
      t.date    :expiration_date, null: false
      t.decimal :strike,          null: false, precision: 10, scale: 4
      t.string  :option_type,     null: false, default: "Call"
      t.integer :dte
      t.decimal :bid,             precision: 10, scale: 4
      t.decimal :ask,             precision: 10, scale: 4
      t.decimal :mid,             precision: 10, scale: 4
      t.decimal :delta,           precision: 8,  scale: 6
      t.decimal :iv,              precision: 8,  scale: 6
      t.integer :open_interest
      t.decimal :underlying_price, precision: 10, scale: 4
      t.datetime :scraped_at,     null: false

      t.timestamps
    end
    add_index :pmcc_leg_quotes, [ :symbol, :expiration_date, :strike ],
              unique: true, name: "idx_pmcc_leg_quotes_unique"
  end
end
