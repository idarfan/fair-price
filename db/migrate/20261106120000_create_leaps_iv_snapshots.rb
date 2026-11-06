# frozen_string_literal: true

# LEAPS IV 環境（leaps-iv-environment.md P1）：每標的每個美東交易日一筆快照。
#
# cm540_atm_iv 只由 LeapsIvEnvironmentService#persist! 寫入（P3），爬蟲不自行計算。
# bc_hv 讀自 Barchart overview 頁，bc_hv_label 固定「HV 30 天」（P0 偵察後使用者裁示）。
# 寫入一律 upsert（symbol, as_of_date），後寫覆蓋先寫：盤中 adhoc 會被收盤後的 scheduled 覆蓋。
class CreateLeapsIvSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :leaps_iv_snapshots do |t|
      t.string   :symbol,       null: false
      t.date     :as_of_date,   null: false  # 美東交易日（取自頁面報價時間）
      t.decimal  :spot,         precision: 12, scale: 4
      t.decimal  :cm540_atm_iv, precision: 8,  scale: 5
      t.decimal  :bc_hv,        precision: 8,  scale: 5
      t.string   :bc_hv_label
      t.string   :source,       null: false  # scheduled / adhoc
      t.datetime :captured_at,  null: false
      t.string   :source_url,   null: false
      t.timestamps
    end

    add_index :leaps_iv_snapshots, %i[symbol as_of_date], unique: true,
              name: "idx_leaps_iv_snapshots_unique"
  end
end
