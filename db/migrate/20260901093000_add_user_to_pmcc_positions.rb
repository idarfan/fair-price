# frozen_string_literal: true

# 2026-09-01 決議翻轉：原本決定不做 per-user 隔離，後來確認真正的風險不是
# 「被別人看到」而是「被別人寫入」——Phase 5 會做建部位／滾倉／平倉表單，
# 沒有 user_id 的話其他 4 個 enabled 帳號不只看得到，還能新增假部位、
# 把持倉標成已平倉、寫進損益帳本，而且事後查不出是誰做的（資料裡沒有「誰」）。
#
# 短腳與帳本不加欄位，透過 position 關聯間接綁定；查詢一律從
# current_user 出發（比照 Api::V1::MarginPositionsController 的做法）。
#
# 此時三張表皆為 0 筆，不需要 backfill。
class AddUserToPmccPositions < ActiveRecord::Migration[8.1]
  def change
    add_reference :pmcc_positions, :user, null: false, foreign_key: true
    add_index :pmcc_positions, [ :user_id, :ticker, :status ]
  end
end
