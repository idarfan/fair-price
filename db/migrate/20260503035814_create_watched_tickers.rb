class CreateWatchedTickers < ActiveRecord::Migration[8.1]
  def change
    create_table :watched_tickers do |t|
      t.string   :ticker,          null: false
      t.datetime :added_at,        null: false
      t.datetime :last_fetched_at
      t.boolean  :active,          null: false, default: true

      t.timestamps
    end
    add_index :watched_tickers, :ticker, unique: true
  end
end
