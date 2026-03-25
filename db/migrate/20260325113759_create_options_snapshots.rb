# frozen_string_literal: true

class CreateOptionsSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :options_snapshots do |t|
      t.string   :symbol,          null: false
      t.string   :expiration_date              # nil = 最近到期日快照
      t.jsonb    :raw_data,        null: false, default: {}
      t.decimal  :current_price,   precision: 10, scale: 4
      t.decimal  :iv_rank,         precision: 5,  scale: 2
      t.decimal  :pc_ratio,        precision: 6,  scale: 4
      t.decimal  :iv_skew,         precision: 6,  scale: 4
      t.datetime :cached_at,       null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :options_snapshots, [:symbol, :expiration_date],
              name: "index_options_snapshots_on_symbol_expiration"
    add_index :options_snapshots, :cached_at
    add_index :options_snapshots, :symbol
  end
end
