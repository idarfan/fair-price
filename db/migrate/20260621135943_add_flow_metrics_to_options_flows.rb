class AddFlowMetricsToOptionsFlows < ActiveRecord::Migration[8.1]
  def change
    add_column :options_flows, :call_premium_total, :bigint
    add_column :options_flows, :put_premium_total, :bigint
    add_column :options_flows, :call_put_ratio, :decimal
    add_column :options_flows, :large_call_count, :integer
    add_column :options_flows, :large_put_count, :integer
    add_column :options_flows, :ask_call_premium, :bigint
    add_column :options_flows, :ask_put_premium, :bigint
    add_column :options_flows, :sweep_block_count, :integer
    add_column :options_flows, :total_trades_loaded, :integer
  end
end
