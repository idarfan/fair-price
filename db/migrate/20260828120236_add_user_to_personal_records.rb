# frozen_string_literal: true

# 稽核 C-2：個人性資料表沒有任何使用者歸屬。
#
# 目前有 5 個 enabled 帳號，這些表卻是全站共用的：任何人都看得到、改得掉、
# 刪得掉別人的資料。最嚴重的是 PortfoliosController#ocr_import 裡的
# Portfolio.delete_all——任何一個使用者匯入截圖，就會清空所有人的持股。
#
# 只針對「個人性」資料加 user_id。TrackedTicker / WatchlistItem / IvWatchlist
# 刻意不動，它們是共用的市場資料與排程來源（見 todo.md 的說明）。
class AddUserToPersonalRecords < ActiveRecord::Migration[8.1]
  TABLES = %i[margin_positions portfolios price_alerts].freeze

  def up
    owner_id = default_owner_id

    TABLES.each do |table|
      add_reference table, :user, foreign_key: true, index: true, null: true

      # 既有資料歸給 admin。沒有 admin 帳號時（例如全新環境）不會有既有資料，
      # 直接跳過即可。
      execute("UPDATE #{table} SET user_id = #{owner_id} WHERE user_id IS NULL") if owner_id

      orphans = select_value("SELECT COUNT(*) FROM #{table} WHERE user_id IS NULL").to_i
      if orphans.positive?
        raise ActiveRecord::IrreversibleMigration,
              "#{table} 還有 #{orphans} 筆資料無法歸屬（找不到 admin 帳號），中止以免資料變成孤兒"
      end

      change_column_null table, :user_id, false
    end
  end

  def down
    TABLES.each do |table|
      remove_reference table, :user, foreign_key: true
    end
  end

  private

  def default_owner_id
    select_value("SELECT id FROM users WHERE admin = TRUE ORDER BY id LIMIT 1") ||
      select_value("SELECT id FROM users ORDER BY id LIMIT 1")
  end
end
