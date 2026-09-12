# frozen_string_literal: true

# 逐根日線 OHLCV（來源：Barchart price-history/daily）。
#
# 為什麼不從 VOLAP 拿：VOLAP 只給分箱統計，沒有 K 棒；而結構型 POI
# （FVG／缺口／Order Block／供需區）與當日高低都需要原始 K 棒。
# interactive-chart 主圖 plot 的 record.storage 實測是空 Map，撈不到逐根資料。
class DailyBar < ApplicationRecord
  # 當日那一根盤中會一直變，所以 fresh window 抓短。
  FRESH_WINDOW = 15.minutes

  # 結構型 POI 的回看根數上限。
  #
  # 原本設 252（一年），但 Barchart 的 price-history/historical 頁面實測只給約
  # 3 個月（SHOP 64 根），而且頁面上沒有日期區間控制項、URL 參數也無效——
  # 要更長得走 Historical Data Download 的 CSV 流程，目前不做。
  #
  # 這不影響功能：52 週高低來自 VOLAP 快照（日線 1 年，實測 94.00–182.19），
  # 不靠這張表；而 FVG／Order Block／供需區這類結構，三個月內的本來就是
  # 最有參考價值的那一段。
  #
  # 上限保留 252 是為了「頁面哪天給更多就自動吃得下」，**不要拿它當有 252 根的保證**，
  # 需要知道實際根數請用 for_symbol(sym).count。
  LOOKBACK_BARS = 252

  validates :symbol, :bar_date, :open_price, :high_price, :low_price, :close_price,
            presence: true

  scope :for_symbol, ->(sym) { where(symbol: sym.to_s.upcase) }
  scope :newest_first, -> { order(bar_date: :desc) }

  def self.fresh_for?(symbol)
    for_symbol(symbol).where(updated_at: FRESH_WINDOW.ago..).exists?
  end

  # 近一年的 K 棒，**由舊到新**排序——結構型 POI 的判斷（FVG 看連續三根、
  # Order Block 看位移根之前那根）全部依賴時間正序，不要在呼叫端各自 reverse。
  def self.lookback(symbol, limit: LOOKBACK_BARS)
    for_symbol(symbol).newest_first.limit(limit).to_a.reverse
  end

  def self.latest_for(symbol)
    for_symbol(symbol).newest_first.first
  end

  # 前一個交易日的收盤，用於「當日區間」卡的前收欄位。
  def self.previous_close(symbol)
    for_symbol(symbol).newest_first.offset(1).first&.close_price
  end

  def range = high_price - low_price
end
