# frozen_string_literal: true

# LEAPS 垂直價差專用的 call chain 快取（leaps-call-spread-spec P1，2026-09-25 改版）。
#
# 與 bcvs 完全分開（使用者裁示：不碰 bcvs）。每檔履約價一列、數值用 decimal 欄位，
# 讀出來就是 BigDecimal，計算路徑不經過 Float。以 (symbol, expiration) 為單位整批
# 取代：一個到期日重抓時先刪後寫，scraped_at 判斷 30 分鐘是否過期。
#
# bid、ask 皆為 0 的履約價也要存（「盤後參考價」規則以 last 計算）。
class CreateLeapsSpreadQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :leaps_spread_quotes do |t|
      t.string   :symbol,           null: false
      t.string   :expiration,       null: false  # Barchart 原始值，例如 "2027-10-15-m"
      t.date     :expiration_date,  null: false
      t.decimal  :strike,           precision: 10, scale: 4, null: false
      t.decimal  :bid,              precision: 10, scale: 4
      t.decimal  :ask,              precision: 10, scale: 4
      t.decimal  :last,             precision: 10, scale: 4
      t.decimal  :delta,            precision: 8,  scale: 6
      t.decimal  :underlying_price, precision: 10, scale: 4
      t.datetime :scraped_at,       null: false
      t.timestamps
    end

    add_index :leaps_spread_quotes, %i[symbol expiration strike], unique: true,
              name: "idx_leaps_spread_quotes_unique"
    add_index :leaps_spread_quotes, %i[symbol expiration scraped_at],
              name: "idx_leaps_spread_quotes_freshness"
  end
end
