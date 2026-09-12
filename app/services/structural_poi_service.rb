# frozen_string_literal: true

# 從日線 K 棒算出「結構型 POI」——供需區 / Order Block / FVG / 缺口。
#
# 這四種在交易圈沒有唯一的標準定義，所以規則全部寫死在常數裡、每條都有測試，
# 而且**每一項都帶 formed_on 日期**，看得出來是哪一段行情留下的。
#
# 輸入的 bars 必須是**由舊到新**（DailyBar.lookback 與 price_history_scraper
# 都已經排好）。倒著傳進來不會報錯，但 FVG／Order Block 的方向會整個相反，
# 所以這裡在入口先自己排一次，不依賴呼叫端守規矩。
class StructuralPoiService
  # 位移根（displacement）：實體漲跌幅達到 ATR 的幾倍才算「一根有意義的推動」。
  #
  # ⚠️ 校準過（feedback_boolean_sort_key）。原本設 1.5，實測 SHOP 與 NOK 各 64 根
  # 日線只找到 2 根與 **0 根**——Order Block 與供需區等於永遠不會出現，
  # 是規則沒在跑，不是市場沒結構。
  #
  # 兩檔的實體/ATR 分佈（前十大）：
  #   SHOP 1.99 1.52 1.47 1.07 0.91 …（中位 0.42）
  #   NOK  1.10 1.05 0.75 0.72 0.71 …（中位 0.20）
  # 1.0（＝實體大於一個 ATR）在兩檔分別給出 4 根與 2 根，數量合理且語意乾淨。
  DISPLACEMENT_ATR_MULTIPLE = 1.0
  # ATR 的回看根數。日線 14 根是業界慣例。
  ATR_PERIOD = 14
  # 供需區：位移根之前連續幾根算「盤整」的最少根數。
  BASE_MIN_BARS = 3

  # 盤整段的全距上限（ATR 的倍數）。
  #
  # ⚠️ 拿實際資料校準過（feedback_boolean_sort_key）。SHOP 64 根日線，
  # 每個位置往回三根的全距 / ATR：最小 0.75、中位 1.77、最大 5.83。
  # 原本寫死「≤ 1 個 ATR」，只有 4 個位置合格，實測產出 **0 個供需區**。
  # 1.5 讓 21 個位置合格，才抓得到真正的盤整。
  BASE_MAX_ATR_MULTIPLE = 1.5

  # 缺口／FVG 的最小寬度（ATR 的倍數）。
  #
  # 同樣是校準出來的：不設下限時 63 根 K 產生 **63 個缺口**——
  # 開盤價幾乎不可能剛好等於前收，等於每天都算一個，完全沒有鑑別度
  # （寬度中位數只有 0.18 ATR）。0.5 ATR 讓缺口剩 9 個、FVG 剩 7 個。
  MIN_SPAN_ATR_MULTIPLE = 0.5
  # 一段缺口／FVG 被回補多少比例就視為失效（完全回補才算失效太寬鬆，
  # 實務上碰到就開始有人接單，取 50%）。
  FILLED_RATIO = 0.5

  Poi = Data.define(:kind, :low, :high, :formed_on, :direction)

  def initialize(bars, current_price: nil)
    @bars = Array(bars).sort_by { |b| b.bar_date }
    @current_price = current_price&.to_f
  end

  # 全部結構型 POI，依價位由低到高。
  # 太窄的、已被回補的、以及重複的都不列入。
  def call
    return [] if @bars.size < ATR_PERIOD + 3

    (fvgs + gaps + order_blocks + supply_demand_zones)
      .reject { |poi| too_narrow?(poi) }
      .reject { |poi| filled?(poi) }
      # 相鄰的兩根位移根常常共用同一根反向 K／同一段盤整，會產生一模一樣的區間。
      # 用 (kind, low, high, formed_on) 去重，保留第一個。
      .uniq { |poi| [ poi.kind, poi.low, poi.high, poi.formed_on ] }
      .sort_by(&:low)
  end

  # --- FVG（Fair Value Gap）-------------------------------------------------
  # 連續三根，第一根與第三根的影線沒有重疊 → 中間那段價格「沒有被成交填滿」。
  #   看漲：bar1.high < bar3.low → 缺口在 [bar1.high, bar3.low]
  #   看跌：bar1.low  > bar3.high → 缺口在 [bar3.high, bar1.low]
  def fvgs
    @bars.each_cons(3).filter_map do |b1, b2, b3|
      if b1.high_price < b3.low_price
        Poi.new(kind: :fvg, low: b1.high_price.to_f, high: b3.low_price.to_f,
                formed_on: b2.bar_date, direction: :bullish)
      elsif b1.low_price > b3.high_price
        Poi.new(kind: :fvg, low: b3.high_price.to_f, high: b1.low_price.to_f,
                formed_on: b2.bar_date, direction: :bearish)
      end
    end
  end

  # --- 缺口（Gap）-----------------------------------------------------------
  # 開盤價相對前一根收盤跳空。與 FVG 不同：FVG 看的是影線的三根結構，
  # 缺口只看「昨收到今開」這一段有沒有被跳過。
  def gaps
    @bars.each_cons(2).filter_map do |prev, cur|
      if cur.open_price > prev.close_price
        Poi.new(kind: :gap, low: prev.close_price.to_f, high: cur.open_price.to_f,
                formed_on: cur.bar_date, direction: :bullish)
      elsif cur.open_price < prev.close_price
        Poi.new(kind: :gap, low: cur.open_price.to_f, high: prev.close_price.to_f,
                formed_on: cur.bar_date, direction: :bearish)
      end
    end
  end

  # --- Order Block ----------------------------------------------------------
  # 位移根之前的**最後一根反向 K**的實體。多頭位移前的最後一根黑K＝需求方的
  # 掛單區；空頭位移前的最後一根紅K＝供給方的掛單區。
  def order_blocks
    displacement_indices.filter_map do |i|
      bullish = @bars[i].close_price > @bars[i].open_price
      ob = last_opposite_bar(i, bullish: bullish)
      next if ob.nil?

      body_low, body_high = [ ob.open_price.to_f, ob.close_price.to_f ].minmax
      # 實體是十字線（開＝收）時區間為零，畫不出來也沒有意義，跳過。
      next if body_high - body_low <= 0

      Poi.new(kind: :order_block, low: body_low, high: body_high,
              formed_on: ob.bar_date, direction: bullish ? :bullish : :bearish)
    end
  end

  # --- 供需區（Supply / Demand Zone）---------------------------------------
  # 位移根之前的窄幅盤整（連續 ≥ BASE_MIN_BARS 根，整段高低全距 ≤ ATR）。
  # 這是「行情起漲／起跌前，籌碼在哪裡換手」的那一塊。
  def supply_demand_zones
    displacement_indices.filter_map do |i|
      base = base_before(i)
      next if base.nil?

      bullish = @bars[i].close_price > @bars[i].open_price
      Poi.new(kind: bullish ? :demand : :supply,
              low: base.map { |b| b.low_price.to_f }.min,
              high: base.map { |b| b.high_price.to_f }.max,
              formed_on: base.last.bar_date,
              direction: bullish ? :bullish : :bearish)
    end
  end

  private

  # 漲跌幅（實體）達到當下 ATR 的 DISPLACEMENT_ATR_MULTIPLE 倍的 K 棒索引。
  def displacement_indices
    @displacement_indices ||= (ATR_PERIOD...@bars.size).select do |i|
      atr = atr_at(i)
      next false if atr.nil? || atr.zero?
      body = (@bars[i].close_price.to_f - @bars[i].open_price.to_f).abs
      body >= atr * DISPLACEMENT_ATR_MULTIPLE
    end
  end

  # 第 i 根當下的 ATR（不含第 i 根本身，避免位移根把自己的門檻墊高）。
  def atr_at(index)
    window = @bars[(index - ATR_PERIOD)...index]
    return nil if window.nil? || window.size < ATR_PERIOD

    trs = window.each_cons(2).map do |prev, cur|
      [ cur.high_price.to_f - cur.low_price.to_f,
        (cur.high_price.to_f - prev.close_price.to_f).abs,
        (cur.low_price.to_f - prev.close_price.to_f).abs ].max
    end
    return nil if trs.empty?
    trs.sum / trs.size
  end

  def last_opposite_bar(index, bullish:)
    (index - 1).downto([ index - 10, 0 ].max) do |j|
      b = @bars[j]
      is_down = b.close_price < b.open_price
      return b if bullish ? is_down : !is_down
    end
    nil
  end

  # 位移根之前的盤整段。從 i-1 往回收集，直到整段全距超過 ATR 為止。
  def base_before(index)
    atr = atr_at(index)
    return nil if atr.nil? || atr.zero?

    base = []
    (index - 1).downto([ index - 10, 0 ].max) do |j|
      candidate = [ @bars[j] ] + base
      span = candidate.map { |b| b.high_price.to_f }.max -
             candidate.map { |b| b.low_price.to_f }.min
      break if span > atr * BASE_MAX_ATR_MULTIPLE
      base = candidate
    end
    base.size >= BASE_MIN_BARS ? base : nil
  end

  # 寬度不到 MIN_SPAN_ATR_MULTIPLE 個 ATR 的缺口／FVG 視為雜訊。
  # Order Block 與供需區不套這條——它們的區間是「籌碼在哪換手」，
  # 本來就可能很窄，窄不代表沒意義。
  def too_narrow?(poi)
    return false unless %i[fvg gap].include?(poi.kind)

    atr = reference_atr
    return false if atr.nil? || atr.zero?
    (poi.high - poi.low) < atr * MIN_SPAN_ATR_MULTIPLE
  end

  # 用最新一根的 ATR 當統一尺規。逐項用「形成當下的 ATR」會讓同樣寬度的缺口
  # 因為形成時的波動不同而一個留一個砍，解讀上更難說明。
  def reference_atr
    @reference_atr ||= atr_at(@bars.size - 1)
  end

  # 形成之後，價格是否已經走回這段區間並吃掉一半以上 → 視為失效。
  # 只看 formed_on **之後**的 K 棒：用形成當下或更早的資料判斷會把自己算進去。
  def filled?(poi)
    later = @bars.select { |b| b.bar_date > poi.formed_on }
    return false if later.empty?

    span = poi.high - poi.low
    return true if span <= 0

    deepest = if poi.direction == :bullish
                # 看漲缺口從上方被往下吃
                poi.high - later.map { |b| b.low_price.to_f }.min
    else
                later.map { |b| b.high_price.to_f }.max - poi.low
    end
    (deepest / span) >= FILLED_RATIO
  end
end
