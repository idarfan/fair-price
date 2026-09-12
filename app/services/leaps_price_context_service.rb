# frozen_string_literal: true

# LEAPS 頁三個 widget（POI / 52 週區間 / 當日區間）的 payload 組裝。
#
# **只讀 DB，不抓網**。抓取是 ScrapePriceContextJob 的事，這裡拿到什麼畫什麼，
# 任一塊缺資料就回 nil 讓 component 降級——不要在這裡丟例外，
# 也不要拿 0 當「沒有資料」的替身（那會在畫面上變成一條長度 0 的區間條，
# 看起來像資料正常但數值為零）。
class LeapsPriceContextService
  def initialize(symbol, user_strike: nil)
    @symbol      = symbol.to_s.upcase
    @user_strike = user_strike
    @snapshot    = VolapSnapshot.latest_for(@symbol)
  end

  def call
    price = current_price
    {
      symbol:        @symbol,
      current_price: price,
      poi:           poi_payload,
      week52:        week52_payload(price),
      day_range:     day_range_payload(price)
    }
  end

  # 三塊都沒有＝這個代號還沒抓過，畫面應該顯示骨架而不是空卡片。
  def any_data? = call.values_at(:poi, :week52, :day_range).any?(&:present?)

  private

  # 現價優先用 LEAPS 快照的 underlying_price——那是排行表與推薦分析用的同一個數字，
  # 三個 widget 跟表格的現價必須一致，不能一邊用收盤一邊用即時報價。
  # 沒有 LEAPS 快照時才退回最新一根日線的收盤。
  def current_price
    @current_price ||=
      LeapsOptionChainSnapshot.latest_underlying_price(@symbol)&.to_f ||
      DailyBar.latest_for(@symbol)&.close_price&.to_f
  end

  def poi_payload
    result = PoiService.new(@symbol, snapshot: @snapshot, user_strike: @user_strike).call
    return nil if result.nil?

    price = current_price
    result.merge(
      current_bin_index: price && @snapshot.bin_index_for(price),
      period_label:      period_label,
      level_size:        @snapshot.inputs["LevelSize"] || @snapshot.bin_count,
      volume_mode:       @snapshot.inputs["Volume"],
      scraped_at:        @snapshot.scraped_at
    )
  end

  # 52 週高低直接取 VOLAP 日線 1 年的價格範圍——實測 SHOP 是 94.00–182.19，
  # 與 52 週高低吻合。不另外從日線算，兩處算同一個數字必然會漂移
  # （何況本地日線只有約 3 個月，根本算不出 52 週）。
  def week52_payload(price)
    return nil if @snapshot.nil?

    low  = @snapshot.price_min.to_f
    high = @snapshot.price_max.to_f
    range_payload(low: low, high: high, price: price)
  end

  def day_range_payload(price)
    bar = DailyBar.latest_for(@symbol)
    return nil if bar.nil?

    payload = range_payload(low: bar.low_price.to_f, high: bar.high_price.to_f, price: price)
    return nil if payload.nil?

    prev_close = DailyBar.previous_close(@symbol)&.to_f
    payload.merge(
      bar_date:   bar.bar_date,
      open:       bar.open_price.to_f,
      prev_close: prev_close,
      change_pct: prev_close && prev_close.positive? ?
                    ((bar.close_price.to_f - prev_close) / prev_close * 100).round(2) : nil,
      amplitude_pct: prev_close && prev_close.positive? ?
                    ((bar.high_price.to_f - bar.low_price.to_f) / prev_close * 100).round(2) : nil
    )
  end

  # 區間條共用的計算。high == low（停牌或單一成交價）時 position 無意義，
  # 回 nil 而不是除以零，也不是硬塞 0%／50%。
  #
  # ⚠️ 現價落在區間外時 **不 clamp**，回 position_pct: nil 並標記 price_outside_range。
  # 原本寫 .clamp(0, 100)，NOK 實測踩到：LEAPS 快照的現價 10.14 是舊的，
  # 當日區間卻是 10.795–10.89，clamp 之後游標被釘在最左邊、畫面看起來一切正常，
  # 實際上是在拿兩個時間點的數字並排（feedback_silent_guards_and_cache）。
  # 寧可不畫游標並讓 component 標示「現價與區間不同步」，也不要畫一個假的位置。
  def range_payload(low:, high:, price:)
    return nil if low.nil? || high.nil? || high <= low

    outside = price && (price < low || price > high)
    span = high - low
    {
      low: low, high: high,
      position_pct: (price && !outside) ? ((price - low) / span * 100).round(1) : nil,
      price_outside_range: !!outside,
      from_high_pct: price && ((price - high) / high * 100).round(1),
      from_low_pct:  price && ((price - low) / low * 100).round(1)
    }
  end

  def period_label
    case @snapshot.period_key
    when "period.1Y" then "日線 1 年"
    when "period.1D" then "5 分鐘 · 當日"
    else "#{@snapshot.period_key} / #{@snapshot.aggregation}"
    end
  end
end
