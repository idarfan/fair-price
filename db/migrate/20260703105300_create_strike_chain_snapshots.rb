class CreateStrikeChainSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :strike_chain_snapshots do |t|
      t.string   :symbol,     null: false
      t.jsonb    :strikes,    null: false, default: []
      t.decimal  :spot_price, precision: 10, scale: 4
      t.datetime :scraped_at, null: false

      t.timestamps
    end

    add_index :strike_chain_snapshots, :symbol, unique: true
  end
end
