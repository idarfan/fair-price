# frozen_string_literal: true

class LeapsOptionChainSnapshot < ApplicationRecord
  # 同一 symbol 在此時間窗內視為 fresh，直接讀 DB 不重新抓取。
  # 唯一權威定義（spec「fresh window 5 → 30 分鐘」節）：model fresh scope、
  # ScrapeLeapsJob 的 Rails.cache expires_in、controller 的 job pending 快取全部引用這裡。
  FRESH_WINDOW = 30.minutes

  validates :symbol, :expiration_date, :strike, :option_type, :scraped_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.upcase) }
  scope :calls,      -> { where(option_type: "Call") }
  scope :fresh,      -> { where(scraped_at: FRESH_WINDOW.ago..) }

  def mid_price
    return nil if bid.nil? && ask.nil?
    return ask if bid.nil?
    return bid if ask.nil?
    (bid + ask) / 2.0
  end
end
