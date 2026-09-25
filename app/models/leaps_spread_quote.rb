# frozen_string_literal: true

# LEAPS 垂直價差專用的 call chain 快取，每檔履約價一列（與 bcvs 的表完全分開）。
# 寫入與讀取一律經過 LeapsSpreadCache。
class LeapsSpreadQuote < ApplicationRecord
  FRESH_WINDOW = 30.minutes

  scope :for_chain, ->(symbol, expiration) { where(symbol: symbol.to_s.upcase, expiration: expiration) }
  scope :fresh,     -> { where(scraped_at: FRESH_WINDOW.ago..) }
end
