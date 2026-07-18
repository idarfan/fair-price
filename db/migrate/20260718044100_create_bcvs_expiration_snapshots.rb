# frozen_string_literal: true

# bcvs.md §快取機制：到期日清單快照，(symbol) 為 key，30 分鐘 TTL，UPSERT
# 不新增重複列（唯一索引為最後防線）。
class CreateBcvsExpirationSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :bcvs_expiration_snapshots do |t|
      t.string   :symbol, null: false
      t.jsonb    :expirations, null: false, default: []
      t.decimal  :underlying_price, precision: 10, scale: 4
      t.datetime :scraped_at, null: false

      t.timestamps
    end

    add_index :bcvs_expiration_snapshots, :symbol, unique: true
  end
end
