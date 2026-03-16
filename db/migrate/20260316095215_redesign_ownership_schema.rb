# frozen_string_literal: true

class RedesignOwnershipSchema < ActiveRecord::Migration[8.1]
  def change
    drop_table :ownership_snapshots, force: :cascade

    create_table :ownership_snapshots do |t|
      t.string  :ticker,            null: false
      t.string  :quarter,           null: false  # "2025-Q4"
      t.date    :snapshot_date,     null: false
      t.decimal :institutional_pct, precision: 6, scale: 2
      t.decimal :insider_pct,       precision: 6, scale: 2
      t.integer :institution_count
      t.timestamps
    end

    add_index :ownership_snapshots, [:ticker, :quarter], unique: true
    add_index :ownership_snapshots, [:ticker, :snapshot_date]

    create_table :ownership_holders do |t|
      t.references :ownership_snapshot, null: false, foreign_key: true
      t.string  :name,         null: false
      t.decimal :pct,          precision: 8, scale: 4
      t.bigint  :market_value
      t.date    :filing_date
      t.timestamps
    end

    add_index :ownership_holders, [:ownership_snapshot_id, :name], unique: true
  end
end
