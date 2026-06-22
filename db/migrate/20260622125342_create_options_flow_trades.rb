class CreateOptionsFlowTrades < ActiveRecord::Migration[8.1]
  def change
    create_table :options_flow_trades do |t|
      t.string   :symbol,        null: false
      t.date     :snapshot_date, null: false
      t.datetime :fetched_at,    null: false

      # CSV columns
      t.string   :option_type                              # "Call" / "Put"
      t.decimal  :strike,     precision: 10, scale: 2
      t.timestamptz :expires_at                            # ISO8601 含時區
      t.integer  :dte
      t.decimal  :trade_price,  precision: 8,  scale: 4
      t.integer  :size
      t.string   :side                                     # "ask" / "bid" / "mid"
      t.bigint   :premium
      t.integer  :volume
      t.integer  :open_interest
      t.decimal  :iv,           precision: 6,  scale: 4
      t.decimal  :delta,        precision: 5,  scale: 4
      t.string   :trade_condition                          # Code 欄
      t.string   :open_close                               # * 欄 (BuyToOpen / SellToOpen / …)
      t.string   :trade_time                               # HH:MM:SS

      # Classification flags
      t.boolean  :is_cancelled,          default: false, null: false
      t.boolean  :is_multi_leg,          default: false, null: false
      t.boolean  :is_stock_combo,        default: false, null: false
      t.boolean  :urgency_high,          default: false, null: false
      t.boolean  :likely_institutional,  default: false, null: false
      t.boolean  :low_liquidity_period,  default: false, null: false
      t.boolean  :timing_anomaly,        default: false, null: false

      t.timestamps
    end

    add_index :options_flow_trades, [ :symbol, :snapshot_date ]
    add_index :options_flow_trades, [ :symbol, :snapshot_date, :is_cancelled, :is_multi_leg ],
              name: "idx_oft_directional"
  end
end
