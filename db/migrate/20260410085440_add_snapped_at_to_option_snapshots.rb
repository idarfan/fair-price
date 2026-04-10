# frozen_string_literal: true

class AddSnappedAtToOptionSnapshots < ActiveRecord::Migration[8.1]
  def up
    add_column :option_snapshots, :snapped_at, :datetime

    # Backfill: treat existing snapshot_date as 20:00 UTC (US market close ~4 PM ET)
    execute "UPDATE option_snapshots SET snapped_at = snapshot_date::timestamp + INTERVAL '20 hours'"

    change_column_null :option_snapshots, :snapped_at, false

    # Drop old date-based unique index
    remove_index :option_snapshots, name: "idx_option_snapshots_unique"

    # New hourly dedup index — allows multiple snapshots per day but only one per hour
    # Rails stores :datetime as UTC without timezone, so date_trunc is IMMUTABLE here
    execute <<~SQL
      CREATE UNIQUE INDEX idx_option_snapshots_hourly
        ON option_snapshots (tracked_ticker_id, date_trunc('hour', snapped_at), contract_symbol)
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_option_snapshots_hourly"

    add_index :option_snapshots, %i[tracked_ticker_id snapshot_date contract_symbol],
              unique: true, name: "idx_option_snapshots_unique"

    remove_column :option_snapshots, :snapped_at
  end
end
