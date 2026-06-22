class CreateMaxPainSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :max_pain_snapshots do |t|
      t.string   :symbol,             null: false
      t.date     :snapshot_date,      null: false
      t.datetime :fetched_at,         null: false
      t.string   :expiration
      t.integer  :dte
      t.decimal  :last_price,         precision: 10, scale: 2
      t.decimal  :max_pain_strike,    precision: 10, scale: 2
      t.jsonb    :strikes,            default: []
      t.jsonb    :call_pain,          default: []
      t.jsonb    :put_pain,           default: []
      t.jsonb    :call_oi,            default: []
      t.jsonb    :put_oi,             default: []
      t.jsonb    :iv_combined,        default: []
      t.jsonb    :max_pain_by_expiry, default: []
      t.timestamps
    end

    add_index :max_pain_snapshots, [ :symbol, :snapshot_date ], unique: true
  end
end
