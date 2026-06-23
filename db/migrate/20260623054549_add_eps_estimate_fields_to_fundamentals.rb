class AddEpsEstimateFieldsToFundamentals < ActiveRecord::Migration[8.1]
  def change
    add_column :fundamentals, :eps_estimate_current_qtr, :decimal
    add_column :fundamentals, :eps_growth_est_yoy, :decimal
    add_column :fundamentals, :eps_prior_year_estimate, :decimal
  end
end
