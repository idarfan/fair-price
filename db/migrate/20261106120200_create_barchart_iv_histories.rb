# frozen_string_literal: true

# LEAPS IV 環境（leaps-iv-environment.md P1）：Barchart Options Overview History 每日一列，
# 是 Barchart IV 指標的唯一來源（IV Rank／Pctl 直接採用頁面值，不自行重算）。
#
# 單位：imp_vol 存小數（0.5192＝51.92%）；iv_rank、iv_pctl 存 0–100
# （頁面資料的 impliedVolatilityPercentile1y 是小數 0.9243，寫入前要 ×100，P0 偵察）。
class CreateBarchartIvHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :barchart_iv_histories do |t|
      t.string   :symbol,         null: false
      t.date     :trade_date,     null: false
      t.decimal  :imp_vol,        precision: 8,  scale: 5
      t.decimal  :iv_rank,        precision: 6,  scale: 2
      t.decimal  :iv_pctl,        precision: 6,  scale: 2
      t.decimal  :pc_vol_ratio,   precision: 8,  scale: 4
      t.bigint   :options_volume
      t.decimal  :pc_oi_ratio,    precision: 8,  scale: 4
      t.bigint   :total_oi
      t.decimal  :last_price,     precision: 12, scale: 4
      t.datetime :captured_at,    null: false
      t.string   :source_url,     null: false
      t.timestamps
    end

    add_index :barchart_iv_histories, %i[symbol trade_date], unique: true,
              name: "idx_barchart_iv_histories_unique"
  end
end
