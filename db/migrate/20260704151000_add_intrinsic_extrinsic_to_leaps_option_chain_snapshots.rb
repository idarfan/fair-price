# frozen_string_literal: true

class AddIntrinsicExtrinsicToLeapsOptionChainSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :leaps_option_chain_snapshots, :intrinsic_value, :decimal, precision: 10, scale: 4
    add_column :leaps_option_chain_snapshots, :extrinsic_value, :decimal, precision: 10, scale: 4

    # Backfill 既有 rows（一次性；公式同 LeapsOptionChainSnapshot.derived_values）。
    # bid/ask/underlying_price 任一缺值 → 維持 null，不存 0 假裝有值。
    up_only do
      execute <<~SQL
        UPDATE leaps_option_chain_snapshots
        SET intrinsic_value = CASE
              WHEN bid IS NULL OR ask IS NULL OR underlying_price IS NULL THEN NULL
              WHEN option_type = 'Put' THEN GREATEST(0, strike - underlying_price)
              ELSE GREATEST(0, underlying_price - strike)
            END,
            extrinsic_value = CASE
              WHEN bid IS NULL OR ask IS NULL OR underlying_price IS NULL THEN NULL
              WHEN option_type = 'Put' THEN (bid + ask) / 2.0 - GREATEST(0, strike - underlying_price)
              ELSE (bid + ask) / 2.0 - GREATEST(0, underlying_price - strike)
            END
      SQL
    end
  end
end
