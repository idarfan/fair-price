class AddVegaToLeapsOptionChainSnapshots < ActiveRecord::Migration[7.2]
  def change
    add_column :leaps_option_chain_snapshots, :vega, :decimal, precision: 10, scale: 6
  end
end
