# frozen_string_literal: true

class CreateSkewRankIntraday < ActiveRecord::Migration[8.1]
  def change
    create_table :skew_rank_intradays do |t|
      t.string :ticker,        null: false
      t.datetime :snapshot_time, null: false
      t.decimal :put_iv_025,    precision: 10, scale: 6
      t.decimal :call_iv_025,   precision: 10, scale: 6
      t.decimal :skew_pts,      precision: 8,  scale: 4
      t.decimal :current_price, precision: 10, scale: 2
      t.timestamps
    end

    add_index :skew_rank_intradays, [ :ticker, :snapshot_time ], unique: true
    add_index :skew_rank_intradays, :snapshot_time
  end
end
