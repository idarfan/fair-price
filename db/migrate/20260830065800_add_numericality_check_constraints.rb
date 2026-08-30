# frozen_string_literal: true

# 稽核（database_consistency NumericalityConstraintChecker）：這些欄位在 model
# 有 `numericality: { greater_than: 0 }`，但 DB 沒有對應的 CHECK 約束——
# 任何繞過驗證的寫入路徑都能塞進 0 或負數。
#
# 金額與股數為負會直接汙染損益計算（Portfolio#total_cost、MarginPosition#balance
# 都是直接相乘），所以這層防護值得放在 DB。
#
# 執行前已確認現有資料違反筆數皆為 0
# （margin_positions 與 portfolios 目前 0 筆，price_alerts 3 筆全部 > 0）。
class AddNumericalityCheckConstraints < ActiveRecord::Migration[8.1]
  # [表, 約束名, 條件]
  # allow_nil 的欄位要寫成 `IS NULL OR ...`，否則 NULL 會讓 CHECK 判定為
  # unknown——PostgreSQL 的 CHECK 在 unknown 時視為通過，寫不寫其實一樣，
  # 但明確寫出來讓意圖不必靠 SQL 三值邏輯的知識去推。
  CONSTRAINTS = [
    [ :price_alerts,     "target_price_positive", "target_price > 0" ],
    [ :margin_positions, "buy_price_positive",    "buy_price > 0" ],
    [ :margin_positions, "shares_positive",       "shares > 0" ],
    [ :margin_positions, "sell_price_positive",   "sell_price IS NULL OR sell_price > 0" ],
    [ :portfolios,       "shares_positive",       "shares > 0" ],
    [ :portfolios,       "unit_cost_positive",    "unit_cost > 0" ],
    [ :portfolios,       "sell_price_positive",   "sell_price IS NULL OR sell_price > 0" ]
  ].freeze

  def up
    CONSTRAINTS.each do |table, name, expression|
      add_check_constraint table, expression, name: name
    end
  end

  def down
    CONSTRAINTS.reverse_each do |table, name, _expression|
      remove_check_constraint table, name: name
    end
  end
end
