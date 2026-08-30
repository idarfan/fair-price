# frozen_string_literal: true

# 稽核（database_consistency ColumnPresenceChecker / ThreeStateBooleanChecker）：
# 這些欄位在 model 有 presence 驗證，但 DB 允許 NULL——繞過驗證的寫入路徑
# （upsert / insert_all / 直接 SQL）就能塞進 NULL。
#
# 執行前已確認現有資料違反筆數皆為 0
# （price_alerts 3 筆、iv_queries 20 筆，NULL 皆為 0）。
class AddNotNullConstraints < ActiveRecord::Migration[8.1]
  def up
    change_column_null :price_alerts, :target_price, false
    change_column_null :iv_queries,   :ticker,       false
    change_column_null :iv_queries,   :option_type,  false

    # 三態 boolean：NULL 與 false 在語意上難以區分，先補 default 再設 NOT NULL。
    # 補 default 是為了讓既有的 INSERT（沒帶這個欄位的）不會因為 NOT NULL 失敗。
    change_column_default :iv_queries, :low_iv_signal, from: nil, to: false
    change_column_null    :iv_queries, :low_iv_signal, false
  end

  def down
    change_column_null    :iv_queries, :low_iv_signal, true
    change_column_default :iv_queries, :low_iv_signal, from: false, to: nil

    change_column_null :iv_queries,   :option_type,  true
    change_column_null :iv_queries,   :ticker,       true
    change_column_null :price_alerts, :target_price, true
  end
end
