class AddMarketQuoteConstraintToOptionSnapshots < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE option_snapshots
        ADD CONSTRAINT chk_option_has_market_quote
        CHECK (bid > 0 OR ask > 0 OR last_price > 0);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE option_snapshots
        DROP CONSTRAINT IF EXISTS chk_option_has_market_quote;
    SQL
  end
end
