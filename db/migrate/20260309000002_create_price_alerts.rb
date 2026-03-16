# frozen_string_literal: true

class CreatePriceAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :price_alerts do |t|
      t.string   :symbol,       null: false
      t.decimal  :target_price, precision: 12, scale: 4
      t.string   :condition,    null: false, default: "above"
      t.boolean  :active,       null: false, default: true
      t.integer  :position,     null: false, default: 0
      t.text     :notes
      t.datetime :triggered_at

      t.timestamps
    end

    add_index :price_alerts, :symbol
    add_index :price_alerts, :position
    add_index :price_alerts, :active
  end
end
