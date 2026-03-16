class CreateOwnershipSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :ownership_snapshots do |t|
      t.string   :symbol,                 null: false
      t.decimal  :institutions_pct,       precision: 5, scale: 2
      t.decimal  :insiders_pct,           precision: 5, scale: 2
      t.decimal  :institutions_float_pct, precision: 5, scale: 2
      t.integer  :institutions_count
      t.jsonb    :top_holders,            default: []
      t.string   :source
      t.datetime :fetched_at,             null: false
      t.timestamps
    end

    add_index :ownership_snapshots, [:symbol, :fetched_at]
    add_index :ownership_snapshots, :symbol
  end
end
