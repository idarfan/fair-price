# frozen_string_literal: true

# 資料表欄位順序的全站設定（一個 table_key 一列）。
#
# 順序是「站台設定」而非個人偏好：只有 admin 能拖曳調整，調完所有人看到的都是
# 同一個順序，換瀏覽器、換裝置都一致——所以存 DB 而不是 localStorage。
class ColumnOrder < ApplicationRecord
  LEAPS_RANKING = "leaps_ranking"

  belongs_to :updated_by, class_name: "User", optional: true

  validates :table_key, presence: true, uniqueness: true

  # 讀出來的順序一律過 sanitize：DB 裡存的是當下那批欄位的快照，日後程式加減
  # 欄位時舊快照會對不上，交給 LeapsTableColumns.sanitize 補正（見該檔說明）。
  def self.keys_for(table_key)
    record = find_by(table_key: table_key)
    LeapsTableColumns.sanitize(record&.column_keys)
  end

  def self.replace!(table_key, keys, user: nil)
    record = find_or_initialize_by(table_key: table_key)
    record.column_keys = Array(keys).map(&:to_s)
    record.updated_by = user
    record.save!
    record
  end
end
