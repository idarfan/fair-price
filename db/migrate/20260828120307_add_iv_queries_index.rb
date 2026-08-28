# frozen_string_literal: true

# 稽核 M-5：iv_queries 是全專案唯一完全沒有索引的表，
# 卻在 Api::IvAnalysisController#watchlist 裡被
# `IvQuery.where(ticker:).order(queried_at: :desc).first` 逐一查詢——
# 每個 watchlist 代號一次全表掃描，而這張表只會越長越大。
class AddIvQueriesIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :iv_queries, [ :ticker, :queried_at ], order: { queried_at: :desc }
  end
end
