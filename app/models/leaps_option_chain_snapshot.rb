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

  # 時間新鮮不夠——還要確認目前存的候選是「為這次要求的中心履約價」爬的。
  # user_strike 每次查詢都可能不同（或這次留空要 auto 偵測、上次卻是手動指定），
  # 只看 scraped_at 會誤把「中心點對不上」的候選當成 cache hit 直接沿用
  # （2026-07-09：NOK 履約價 7 查出跟輸入無關的 $12 候選）。
  # controller 的 fresh_data_exists? 與 BarchartScraperService#fetch_leaps 內部
  # 自己的 cache 短路，都必須呼叫這個唯一權威判斷，不能各自重寫一份。
  def self.fresh_for?(symbol, user_strike: nil)
    return false unless for_symbol(symbol).fresh.exists?

    requested   = user_strike.present? ? user_strike.to_f : nil
    last_center = StrikeChainSnapshot.find_by(symbol: symbol.upcase)&.last_query_strike&.to_f
    last_center == requested
  end

  def mid_price
    return nil if bid.nil? && ask.nil?
    return ask if bid.nil?
    return bid if ask.nil?
    (bid + ask) / 2.0
  end

  # Phase H：內在/外在價值的唯一公式定義處。persist 層（BarchartScraperService#persist_leaps／
  # #persist_pmcc_short_calls）寫入時呼叫；排行層直接讀 DB 欄位，不得重算（雙軌計算是規格明文
  # 禁止的 bug 溫床）。
  # PMCC v3 §2.1：mid 的決定（Barchart midpoint 原值 → fallback (bid+ask)/2 → 任一缺值則 null）
  # 由呼叫端決定並傳入，本方法不得自行從 bid/ask 重算——同一列的 mid_price 欄與這裡算
  # extrinsic_value 用的 mid 必須是同一個數字。LEAPS 呼叫端傳 (bid+ask)/2（無獨立 midpoint
  # 欄位可用），行為與改版前一致。
  # mid/underlying_price 任一缺值 → 兩欄皆 null，不存 0 假裝有值。
  def self.derived_values(option_type:, strike:, underlying_price:, mid:)
    return { intrinsic_value: nil, extrinsic_value: nil } if mid.nil? || underlying_price.nil?

    intrinsic = if option_type.to_s.casecmp("put").zero?
                  [ strike.to_f - underlying_price.to_f, 0.0 ].max
    else
                  [ underlying_price.to_f - strike.to_f, 0.0 ].max
    end
    { intrinsic_value: intrinsic, extrinsic_value: mid.to_f - intrinsic }
  end
end
