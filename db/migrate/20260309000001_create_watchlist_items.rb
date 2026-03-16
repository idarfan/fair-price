# frozen_string_literal: true

class CreateWatchlistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :watchlist_items do |t|
      t.string  :symbol,   null: false
      t.string  :name
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :watchlist_items, :symbol,   unique: true
    add_index :watchlist_items, :position
  end
end
