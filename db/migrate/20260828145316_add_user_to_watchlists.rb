# frozen_string_literal: true

# 稽核 C-2 第二階段：兩份「觀察清單」加上使用者歸屬。
#
# 這兩張表都有排程在讀（`ouou-pre-market` 讀 watchlist_items、
# `iv-skew-snapshot` / `iv-skew-intraday` / backfill_iv_skew.py 讀 iv_watchlists），
# 排程沒有 current_user，所以改成「排程取所有使用者的聯集」：
# 蒐集出來的資料（iv_daily_snapshots / skew_rank_*）本來就是 ticker-keyed，
# 一個代號只會有一份，不會因為多人追蹤而重複。
#
# 既有資料全部歸給 admin，所以聯集 == 目前的集合，排程行為完全不變。
#
# tracked_tickers 刻意不在這裡：option_snapshots 綁 tracked_ticker_id 且有 79 萬列，
# 分人需要先把它改成 symbol-keyed，成本高很多；改為限制只有 admin 能寫入。
class AddUserToWatchlists < ActiveRecord::Migration[8.1]
  TABLES = %i[watchlist_items iv_watchlists].freeze

  def up
    owner_id = default_owner_id

    TABLES.each do |table|
      add_reference table, :user, foreign_key: true, index: true, null: true

      execute("UPDATE #{table} SET user_id = #{owner_id} WHERE user_id IS NULL") if owner_id

      orphans = select_value("SELECT COUNT(*) FROM #{table} WHERE user_id IS NULL").to_i
      if orphans.positive?
        raise ActiveRecord::IrreversibleMigration,
              "#{table} 還有 #{orphans} 筆資料無法歸屬（找不到 admin 帳號），中止以免資料變成孤兒"
      end

      change_column_null table, :user_id, false
    end

    # symbol 的唯一性從「全站唯一」改成「每個使用者各自唯一」，
    # 否則第二個使用者連加入同一個代號都會被擋。
    remove_index :watchlist_items, :symbol
    add_index    :watchlist_items, [ :user_id, :symbol ], unique: true

    remove_index :iv_watchlists, :symbol
    add_index    :iv_watchlists, [ :user_id, :symbol ], unique: true
  end

  def down
    remove_index :watchlist_items, [ :user_id, :symbol ]
    remove_index :iv_watchlists,   [ :user_id, :symbol ]

    TABLES.each { |table| remove_reference table, :user, foreign_key: true }

    add_index :watchlist_items, :symbol, unique: true
    add_index :iv_watchlists,   :symbol, unique: true
  end

  private

  def default_owner_id
    select_value("SELECT id FROM users WHERE admin = TRUE ORDER BY id LIMIT 1") ||
      select_value("SELECT id FROM users ORDER BY id LIMIT 1")
  end
end
