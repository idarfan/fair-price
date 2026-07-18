# frozen_string_literal: true

# bcvs.md §快取機制：指定到期日的 call chain 快照，(symbol, expiration) 為
# key，30 分鐘 TTL。strikes JSONB 陣列存 [{strike,bid,ask,mid,open_interest,...}]，
# bid=0/OI=0 已由 BcvsCacheService 過濾後才寫入。
class CreateBcvsChainSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :bcvs_chain_snapshots do |t|
      t.string   :symbol, null: false
      t.string   :expiration, null: false
      t.jsonb    :strikes, null: false, default: []
      t.decimal  :underlying_price, precision: 10, scale: 4
      t.datetime :scraped_at, null: false

      t.timestamps
    end

    add_index :bcvs_chain_snapshots, %i[symbol expiration], unique: true
  end
end
