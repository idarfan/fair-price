class CreateIvDailySnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :iv_daily_snapshots do |t|
      t.string  :ticker,        null: false
      t.date    :snapshot_date, null: false
      t.decimal :atm_iv,        precision: 8, scale: 4
      t.decimal :atm_strike,    precision: 10, scale: 2
      t.decimal :current_price, precision: 10, scale: 2

      t.timestamps
    end
    add_index :iv_daily_snapshots, [:ticker, :snapshot_date], unique: true
  end
end
