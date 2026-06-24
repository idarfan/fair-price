class RefactorMaxPainSnapshots < ActiveRecord::Migration[8.1]
  def change
    # 1. 新表：存 Max Pain by Contract（不受篩選影響，symbol+date 唯一）
    create_table :max_pain_contract_snapshots do |t|
      t.string   :symbol,             null: false
      t.date     :snapshot_date,      null: false
      t.datetime :fetched_at,         null: false
      t.jsonb    :max_pain_by_expiry, default: []
      t.timestamps
    end
    add_index :max_pain_contract_snapshots, [:symbol, :snapshot_date], unique: true

    # 2. 修改 max_pain_snapshots
    remove_index :max_pain_snapshots, [:symbol, :snapshot_date]

    # 2b. 舊資料全刪（11 筆測試資料，expiration 皆為 null 或假 symbol）
    execute "DELETE FROM max_pain_snapshots"

    change_column_null :max_pain_snapshots, :expiration, false

    add_column :max_pain_snapshots, :strikes_filter,   :string, null: false, default: "show_all"
    add_column :max_pain_snapshots, :volume_oi_filter, :string, null: false, default: "open_interest"

    remove_column :max_pain_snapshots, :max_pain_by_expiry

    add_index :max_pain_snapshots,
              [:symbol, :snapshot_date, :expiration, :strikes_filter, :volume_oi_filter],
              unique: true,
              name: "idx_max_pain_snapshots_filter_unique"
  end
end
