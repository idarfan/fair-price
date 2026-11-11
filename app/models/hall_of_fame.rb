# frozen_string_literal: true

# 投資名人堂（hall-of-fame-spec.md）的命名空間；所有 model 對應 hof_ 前綴的資料表。
module HallOfFame
  def self.table_name_prefix
    "hof_"
  end
end
