# frozen_string_literal: true

# Barchart interactive-chart 的 VOLAP（Volume Profile）指標算好的分箱結果。
#
# 重要：POC 與 Value Area 是 **Barchart 算的**，本專案不重算也不校正。
# 存取路徑與三個踩過的前提見 reference_barchart_volap_dom 記憶。
class VolapSnapshot < ApplicationRecord
  # 同一 symbol 在此時間窗內視為 fresh，直接讀 DB 不重新抓取。
  # 唯一權威定義：model 的 fresh scope、job 的 cache expires_in、controller 的
  # pending 判斷全部引用這裡，不各自寫一份（同 LeapsOptionChainSnapshot 的作法）。
  FRESH_WINDOW = 15.minutes

  # 爬蟲固定切到的設定。VOLAP 是 periodType: "VisibleScreen"，
  # 不固定期間的話每次抓到的數字都不一樣，所以這兩個值寫死在這裡當唯一來源。
  TARGET_PERIOD_KEY  = "period.1Y"
  TARGET_AGGREGATION = "CHART.DAILY"

  validates :symbol, :scraped_at, :period_key, :aggregation,
            :price_min, :price_max, :zone, :poc_index, presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }
  scope :fresh,      -> { where(scraped_at: FRESH_WINDOW.ago..) }
  scope :recent_first, -> { order(scraped_at: :desc) }

  def self.fresh_for?(symbol)
    for_symbol(symbol).fresh.exists?
  end

  def self.latest_for(symbol)
    for_symbol(symbol).recent_first.first
  end

  # 第 i 箱的價格區間。zone 是 Barchart 給的箱高，不自行由 (max-min)/n 反推——
  # 反推會因浮點誤差跟 Barchart 的分箱邊界對不齊。
  def bin_range(index)
    low = price_min + zone * index
    [ low, low + zone ]
  end

  def bin_count = Array(bars).size

  # 價位落在哪一箱；超出範圍回 nil（呼叫端據此決定不標這個 POI）。
  def bin_index_for(price)
    return nil if price.nil?
    value = price.to_f
    return nil if value < price_min.to_f || value > price_max.to_f

    idx = ((value - price_min.to_f) / zone.to_f).floor
    idx.clamp(0, [ bin_count - 1, 0 ].max)
  end
end
