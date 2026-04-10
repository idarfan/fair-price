# frozen_string_literal: true

class CreateTrackedTickers < ActiveRecord::Migration[8.1]
  def change
    create_table :tracked_tickers do |t|
      t.string  :symbol, null: false
      t.string  :name
      t.boolean :active, default: true, null: false
      t.jsonb   :config, default: {}, null: false
      t.timestamps
    end

    add_index :tracked_tickers, :symbol, unique: true
    add_index :tracked_tickers, :active
  end
end
