class AddAvailableExpirationsToMaxPainContractSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :max_pain_contract_snapshots, :available_expirations, :jsonb, default: []
  end
end
