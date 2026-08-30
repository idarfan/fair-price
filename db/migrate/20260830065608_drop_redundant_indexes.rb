# frozen_string_literal: true

# 稽核（database_consistency RedundantIndexChecker）：七個單欄索引被同表的
# 複合索引以 leftmost prefix 完全涵蓋，PostgreSQL 不會用到它們，只是白白
# 佔空間並拖慢每次寫入。
#
# 逐一用 pg_indexes 驗證過涵蓋關係成立且**沒有 partial index**——
# 複合索引若帶 WHERE 條件就不能涵蓋單欄索引，該工具不會檢查這點。
class DropRedundantIndexes < ActiveRecord::Migration[8.1]
  # [表, 要刪的欄位, 涵蓋它的複合索引]
  REDUNDANT = [
    [ :watchlist_items,     :user_id,                 "index_watchlist_items_on_user_id_and_symbol" ],
    [ :user_activities,     :user_id,                 "index_user_activities_on_user_id_and_kind_and_started_at" ],
    [ :ownership_holders,   :ownership_snapshot_id,   "index_ownership_holders_on_ownership_snapshot_id_and_name" ],
    [ :option_snapshots,    :tracked_ticker_id,       "idx_option_snapshots_hourly" ],
    [ :margin_positions,    :status,                  "index_margin_positions_on_status_and_opened_on" ],
    [ :iv_watchlists,       :user_id,                 "index_iv_watchlists_on_user_id_and_symbol" ]
  ].freeze

  def up
    REDUNDANT.each do |table, column, _covered_by|
      remove_index table, column if index_exists?(table, column)
    end

    # 這個是複合索引被另一個更長的複合索引涵蓋，欄位寫法不同故單獨處理
    if index_exists?(:options_flow_trades, [ :symbol, :snapshot_date ])
      remove_index :options_flow_trades, [ :symbol, :snapshot_date ]
    end
  end

  def down
    REDUNDANT.each do |table, column, _covered_by|
      add_index table, column unless index_exists?(table, column)
    end

    unless index_exists?(:options_flow_trades, [ :symbol, :snapshot_date ])
      add_index :options_flow_trades, [ :symbol, :snapshot_date ]
    end
  end
end
