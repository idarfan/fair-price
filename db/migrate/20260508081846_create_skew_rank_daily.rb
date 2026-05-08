class CreateSkewRankDaily < ActiveRecord::Migration[8.1]
  def change
    create_table :skew_rank_daily do |t|
      t.string  :ticker,        null: false
      t.date    :snapshot_date, null: false
      t.decimal :put_iv_025,  precision: 8, scale: 6
      t.decimal :call_iv_025, precision: 8, scale: 6
      t.decimal :skew_pts,    precision: 6, scale: 2
      t.decimal :skew_rank,   precision: 5, scale: 2
      t.timestamps
    end
    add_index :skew_rank_daily, [ :ticker, :snapshot_date ], unique: true
  end
end
