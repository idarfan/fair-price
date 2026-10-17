# frozen_string_literal: true

# 投資名人堂 P3b：hof_sync_runs 加 kind（index／pdf_parse／options）。
# 期權批次要把 CDP 離線訊息寫進 error_log，但 P2 以「最近一筆已結束的 house run」
# 取條件式請求的 validators；不分 kind 的話期權 run 會讓 P2 取到空的 validators。
# 既有列都是 P2 的索引同步，預設 index。
class AddKindToHofSyncRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :hof_sync_runs, :kind, :string, null: false, default: "index"
    remove_index :hof_sync_runs, %i[source started_at]
    add_index :hof_sync_runs, %i[source kind started_at]
  end
end
