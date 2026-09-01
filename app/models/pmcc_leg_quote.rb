# frozen_string_literal: true

# 被追蹤的腳（目前只有 PMCC 長腳）的最新報價，由
# pmcc_short_call_scraper.py 的 --expirations 路徑取得（Phase 0）。
#
# **覆蓋式快照，不是時間序列**：(symbol, expiration_date, strike) 有唯一索引，
# 每次抓取覆蓋同一列。要回溯「當時的建議用了什麼報價」必須在建立
# PmccPnlEvent 時把報價寫進 quote_snapshot，事後查不到。
class PmccLegQuote < ApplicationRecord
  SYMBOL_FORMAT = /\A[A-Za-z0-9.\-]{1,10}\z/

  before_validation { self.symbol = symbol&.upcase&.strip }

  validates :symbol, presence: true, format: { with: SYMBOL_FORMAT }
  validates :strike, numericality: { greater_than: 0 }
  validates :expiration_date, :scraped_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }

  def self.for_leg(symbol, expiration_date, strike)
    for_symbol(symbol).find_by(expiration_date: expiration_date, strike: strike)
  end
end
