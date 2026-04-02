# frozen_string_literal: true

class CreateMarginPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :margin_positions do |t|
      t.string   :symbol,     null: false
      t.decimal  :buy_price,  precision: 15, scale: 4, null: false
      t.decimal  :shares,     precision: 15, scale: 5, null: false
      t.decimal  :sell_price, precision: 15, scale: 4
      t.date     :opened_on,  null: false
      t.date     :closed_on
      t.string   :status,     null: false, default: "open"
      t.integer  :position,   null: false, default: 0
      t.timestamps
    end

    add_index :margin_positions, :status
    add_index :margin_positions, [ :status, :opened_on ]
  end
end
