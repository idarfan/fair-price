class AddLastQueryStrikeToStrikeChainSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :strike_chain_snapshots, :last_query_strike, :decimal, precision: 10, scale: 4
  end
end
