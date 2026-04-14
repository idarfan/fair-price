class RemoveZeroBidAskOptionSnapshots < ActiveRecord::Migration[8.1]
  def up
    deleted = execute("DELETE FROM option_snapshots WHERE bid = 0 AND ask = 0").cmd_tuples
    Rails.logger.info "Removed #{deleted} zero bid/ask option snapshots"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
