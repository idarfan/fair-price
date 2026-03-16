# frozen_string_literal: true

class ChangeOwnershipSnapshotsUniqueKeyToTickerDate < ActiveRecord::Migration[8.1]
  def change
    remove_index :ownership_snapshots, [:ticker, :quarter]
    remove_index :ownership_snapshots, [:ticker, :snapshot_date]
    add_index    :ownership_snapshots, [:ticker, :snapshot_date], unique: true
  end
end
