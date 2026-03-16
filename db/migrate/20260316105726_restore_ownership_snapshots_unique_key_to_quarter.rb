# frozen_string_literal: true

class RestoreOwnershipSnapshotsUniqueKeyToQuarter < ActiveRecord::Migration[8.1]
  def change
    # 清除同一季度的重複記錄（保留每個 ticker+quarter 的最新一筆）
    execute <<~SQL
      DELETE FROM ownership_snapshots
      WHERE id NOT IN (
        SELECT DISTINCT ON (ticker, quarter) id
        FROM ownership_snapshots
        ORDER BY ticker, quarter, snapshot_date DESC
      )
    SQL

    remove_index :ownership_snapshots, [:ticker, :snapshot_date]
    add_index    :ownership_snapshots, [:ticker, :quarter], unique: true
    add_index    :ownership_snapshots, [:ticker, :snapshot_date]
  end
end
