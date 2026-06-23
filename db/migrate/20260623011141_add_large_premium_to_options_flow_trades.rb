class AddLargePremiumToOptionsFlowTrades < ActiveRecord::Migration[8.1]
  def change
    add_column :options_flow_trades, :large_premium, :boolean, default: false, null: false
  end
end
