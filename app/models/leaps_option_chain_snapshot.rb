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

  # Phase H：內在/外在價值的唯一公式定義處。persist 層（BarchartScraperService#persist_leaps）
  # 寫入時呼叫；排行層直接讀 DB 欄位，不得重算（雙軌計算是規格明文禁止的 bug 溫床）。
  # 權利金基準是 Mid = (bid+ask)/2，不是 last_price（Latest 可能是數小時前的陳舊成交價）。
  # bid/ask/underlying_price 任一缺值 → 兩欄皆 null，不存 0 假裝有值。
  def self.derived_values(option_type:, strike:, underlying_price:, bid:, ask:)
    return { intrinsic_value: nil, extrinsic_value: nil } if bid.nil? || ask.nil? || underlying_price.nil?

    mid       = (bid.to_f + ask.to_f) / 2.0
    intrinsic = if option_type.to_s.casecmp("put").zero?
                  [ strike.to_f - underlying_price.to_f, 0.0 ].max
                else
                  [ underlying_price.to_f - strike.to_f, 0.0 ].max
                end
    { intrinsic_value: intrinsic, extrinsic_value: mid - intrinsic }
  end
end
