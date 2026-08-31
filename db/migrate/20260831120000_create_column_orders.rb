# frozen_string_literal: true

# 資料表欄位順序的全站設定。一個 table_key 一列，本次只用到 "leaps_ranking"；
# 日後 PMCC 表也要可拖曳時，多一列即可，不需要再開一張表。
class CreateColumnOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :column_orders do |t|
      t.string  :table_key,   null: false
      t.jsonb   :column_keys, null: false, default: []
      t.references :updated_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end

    add_index :column_orders, :table_key, unique: true
  end
end
