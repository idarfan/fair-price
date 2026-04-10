# frozen_string_literal: true

class CreateOptionSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :option_snapshots do |t|
      t.references :tracked_ticker, null: false, foreign_key: true

      t.date    :snapshot_date,      null: false
      t.string  :contract_symbol,   null: false
      t.string  :option_type,       null: false
      t.date    :expiration,        null: false
      t.decimal :strike,            precision: 10, scale: 4, null: false
      t.decimal :last_price,        precision: 10, scale: 4
      t.decimal :bid,               precision: 10, scale: 4
      t.decimal :ask,               precision: 10, scale: 4
      t.integer :volume
      t.integer :open_interest
      t.decimal :implied_volatility, precision: 8, scale: 6
      t.boolean :in_the_money,      default: false, null: false
      t.decimal :underlying_price,  precision: 10, scale: 4

      t.timestamps
    end

    add_index :option_snapshots,
              %i[tracked_ticker_id snapshot_date contract_symbol],
              unique: true, name: "idx_option_snapshots_unique"
    add_index :option_snapshots, :expiration
    add_index :option_snapshots, %i[option_type strike]
    add_index :option_snapshots, :snapshot_date
  end
end
