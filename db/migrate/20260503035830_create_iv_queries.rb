class CreateIvQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :iv_queries do |t|
      t.string  :ticker
      t.decimal :strike,       precision: 10, scale: 2
      t.date    :expiry_date
      t.string  :option_type
      t.decimal :current_price, precision: 10, scale: 2
      t.decimal :delta,         precision: 6,  scale: 4
      t.decimal :iv,            precision: 8,  scale: 4
      t.decimal :ivr_1y,        precision: 6,  scale: 2
      t.decimal :ivp_1y,        precision: 6,  scale: 2
      t.decimal :ivr_2y,        precision: 6,  scale: 2
      t.decimal :ivp_2y,        precision: 6,  scale: 2
      t.integer :available_days
      t.string  :data_quality
      t.boolean :low_iv_signal
      t.datetime :queried_at

      t.timestamps
    end
  end
end
