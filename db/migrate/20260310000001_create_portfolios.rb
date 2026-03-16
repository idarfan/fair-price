# frozen_string_literal: true

class CreatePortfolios < ActiveRecord::Migration[8.1]
  def change
    create_table :portfolios do |t|
      t.string  :symbol,     null: false
      t.decimal :shares,     precision: 15, scale: 5, null: false
      t.decimal :unit_cost,  precision: 15, scale: 5, null: false
      t.decimal :sell_price, precision: 15, scale: 2
      t.integer :position,   null: false, default: 0
      t.timestamps
    end

    add_index :portfolios, :symbol
  end
end
