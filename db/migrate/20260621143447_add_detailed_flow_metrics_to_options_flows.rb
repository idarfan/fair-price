class AddDetailedFlowMetricsToOptionsFlows < ActiveRecord::Migration[8.1]
  def change
    add_column :options_flows, :ask_call_put_ratio, :decimal
    add_column :options_flows, :high_delta_call_count, :integer
    add_column :options_flows, :long_dte_call_premium, :bigint
    add_column :options_flows, :short_dte_put_premium, :bigint
    add_column :options_flows, :top_large_orders, :jsonb
  end
end
