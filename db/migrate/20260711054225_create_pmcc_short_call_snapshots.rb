class CreatePmccShortCallSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :pmcc_short_call_snapshots do |t|
      t.string   :symbol,             null: false
      t.date     :expiration_date,    null: false
      t.integer  :dte
      t.decimal  :strike,             precision: 10, scale: 4, null: false
      t.string   :option_type,        null: false, default: "Call"
      t.decimal  :bid,                precision: 10, scale: 4
      t.decimal  :ask,                precision: 10, scale: 4
      t.decimal  :mid_price,          precision: 10, scale: 4
      t.decimal  :last_price,         precision: 10, scale: 4
      t.decimal  :moneyness,          precision: 8,  scale: 4
      t.decimal  :underlying_price,   precision: 10, scale: 4
      t.decimal  :change,             precision: 10, scale: 4
      t.decimal  :percent_change,     precision: 8,  scale: 4
      t.integer  :volume
      t.integer  :open_interest
      t.integer  :oi_change
      t.decimal  :vol_oi_ratio,       precision: 8,  scale: 4
      t.decimal  :iv,                 precision: 8,  scale: 6
      t.decimal  :delta,              precision: 8,  scale: 6
      t.decimal  :gamma,              precision: 10, scale: 6
      t.decimal  :theta,              precision: 10, scale: 6
      t.decimal  :vega,               precision: 10, scale: 6
      t.decimal  :rho,                precision: 10, scale: 6
      t.decimal  :theoretical_price,  precision: 10, scale: 4
      t.decimal  :itm_probability,    precision: 8,  scale: 6
      t.decimal  :intrinsic_value,    precision: 10, scale: 4
      t.decimal  :extrinsic_value,    precision: 10, scale: 4
      t.date     :last_trade_date
      t.datetime :scraped_at,         null: false
      t.timestamps
    end
    add_index :pmcc_short_call_snapshots, [ :symbol, :expiration_date, :strike ],
              unique: true, name: "idx_pmcc_short_unique"
    add_index :pmcc_short_call_snapshots, [ :symbol, :scraped_at ],
              name: "idx_pmcc_short_symbol_scraped"
  end
end
