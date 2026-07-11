# frozen_string_literal: true

class PmccShortCallSnapshot < ApplicationRecord
  # PMCC v3 §5：唯一權威定義引用 LeapsOptionChainSnapshot::FRESH_WINDOW，禁自訂第二個 30.minutes。
  FRESH_WINDOW = LeapsOptionChainSnapshot::FRESH_WINDOW

  validates :symbol, :expiration_date, :strike, :option_type, :scraped_at, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.upcase) }
  scope :fresh,      -> { where(scraped_at: FRESH_WINDOW.ago..) }

  def self.fresh_for?(symbol)
    for_symbol(symbol).fresh.exists?
  end

  # §2.1 的 mid 決定順序在 persist 層（BarchartScraperService#persist_pmcc_short_calls）
  # 已經算好存進 mid_price 欄——這裡只是讀取層防禦性 fallback（理論上不該用到，
  # 因為 persist 已經算過；若舊資料或未走 persist 路徑寫入導致 mid_price 缺值，
  # 才會退回 (bid+ask)/2），不是第二份計算公式，兩者決定順序完全一致。
  def mid_price
    stored = self[:mid_price]
    return stored if stored.present?
    return nil if bid.nil? || ask.nil?
    (bid + ask) / 2.0
  end
end
