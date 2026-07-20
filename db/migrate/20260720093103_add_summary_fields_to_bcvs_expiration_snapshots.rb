# frozen_string_literal: true

# bcvs.md §功能流程 步驟1（v4）：標的摘要五值隨到期日清單同快取，欄位皆為
# 可為 null 的抓取結果（DOM 抓不到就是 null，不得造值）。
class AddSummaryFieldsToBcvsExpirationSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :bcvs_expiration_snapshots, :price_change,    :decimal, precision: 10, scale: 4
    add_column :bcvs_expiration_snapshots, :iv_atm,          :decimal, precision: 8,  scale: 4
    add_column :bcvs_expiration_snapshots, :hv,              :decimal, precision: 8,  scale: 4
    add_column :bcvs_expiration_snapshots, :iv_rank,         :decimal, precision: 8,  scale: 4
    add_column :bcvs_expiration_snapshots, :latest_earnings, :string
  end
end
