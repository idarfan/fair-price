class AddPctChangeToOwnershipHolders < ActiveRecord::Migration[8.1]
  def change
    add_column :ownership_holders, :pct_change, :decimal, precision: 8, scale: 4
  end
end
