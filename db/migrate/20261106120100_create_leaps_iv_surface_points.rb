# frozen_string_literal: true

# LEAPS IV 環境（leaps-iv-environment.md P1）：IV 曲面的原始點，
# 每標的 × 美東交易日 × 到期日 × 履約價一列（moneyness 0.60–1.25 的 call）。
#
# expiration、strike 是唯一索引的一部分，設 not null：PostgreSQL 唯一索引不把 NULL 視為相等，
# 允許 NULL 會讓 upsert 寫出重複列。寫入規則同 leaps_iv_snapshots（upsert，後寫覆蓋先寫）。
class CreateLeapsIvSurfacePoints < ActiveRecord::Migration[8.1]
  def change
    create_table :leaps_iv_surface_points do |t|
      t.string   :symbol,      null: false
      t.date     :as_of_date,  null: false
      t.date     :expiration,  null: false
      t.integer  :dte
      t.decimal  :strike,      precision: 12, scale: 4, null: false
      t.decimal  :moneyness,   precision: 6,  scale: 4
      t.decimal  :call_iv,     precision: 8,  scale: 5
      t.decimal  :delta,       precision: 6,  scale: 4
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :leaps_iv_surface_points, %i[symbol as_of_date expiration strike], unique: true,
              name: "idx_leaps_iv_surface_points_unique"
  end
end
