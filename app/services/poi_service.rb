# frozen_string_literal: true

# 把四類來源合成一份「關注價位（POI）」清單，掛在 VOLAP 的分箱上。
#
# POI ≠ POC。POC 只是 POI 的其中一項——POI 是「交易者會盯的關鍵價區」這個
# 更大的集合，本服務納入：
#   1. 量價節點：POC / HVN / LVN（← VolapParserService，Barchart 算好的）
#   2. 結構型：FVG / 缺口 / Order Block / 供需區（← StructuralPoiService）
#   3. 選擇權大 OI 履約價（← LeapsOptionChainSnapshot；使用者輸入的履約價一律納入）
#   4. 重要均線 MA20/50/100/200（← TechnicalAnalysis，DB 現成，不重算）
#
# 標籤掛在箱上而不是另建價格軸：日線 1 年的 VOLAP 範圍實測涵蓋 52 週高低
# （SHOP 94.00–182.19），所有 POI 都落得進去。落在範圍外的會被
# VolapSnapshot#bin_index_for 擋掉回 nil，這裡就不標——寧可少標一個，
# 也不要把區間外的東西硬塞到最上或最下那一箱假裝有對應。
class PoiService
  # 大 OI 履約價取前幾名。取太多會讓每一箱都有標籤，等於沒有標籤。
  TOP_OI_STRIKES = 3

  # 只取前 N 名不夠——名次不代表量體。SHOP 的鏈裡只有兩個履約價
  # （100 是 5857 口、119 是 **2 口**），第二名就這樣被標成「大 OI 履約價」。
  # 加一道相對門檻：未平倉量要達到最大者的 10% 才算「大」。
  MIN_OI_RATIO_OF_TOP = 0.10

  MA_LABELS = {
    ma_20d: "MA20", ma_50d: "MA50", ma_100d: "MA100", ma_200d: "MA200"
  }.freeze

  def initialize(symbol, snapshot: nil, user_strike: nil)
    @symbol      = symbol.to_s.upcase
    @snapshot    = snapshot || VolapSnapshot.latest_for(@symbol)
    @user_strike = user_strike.presence&.to_f
  end

  # 回傳 { bins:, labels_by_bin: }；bins 由低到高（畫面自己 reverse）。
  # 沒有 VOLAP 快照就回 nil，讓 component 走降級顯示而不是畫半張圖。
  def call
    return nil if @snapshot.nil?

    parser = VolapParserService.new(@snapshot)
    bins   = parser.bins
    return nil if bins.empty?

    { bins: bins, labels_by_bin: labels_by_bin(parser) }
  end

  private

  # bin index => 該箱的標籤陣列，每項是 { label:, tip: }。
  #
  # tip 是 tooltips.js 的 data-tip-key：滑過看解釋、點擊看 driver.js 聚光說明。
  # 名詞（POC / HVN / LVN / FVG / Order Block / 供需區…）對一般使用者不是常識，
  # 光把縮寫印在圖上等於沒說（使用者實測回報「沒有解釋 FVG、LVN、POC、POI」）。
  def labels_by_bin(parser)
    entries = volume_node_entries(parser) +
              structural_entries +
              option_strike_entries +
              moving_average_entries

    entries
      .filter_map { |e| (idx = bin_index_for(e)) && [ idx, { label: e[:label], tip: e[:tip] } ] }
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).uniq { |l| l[:label] } }
  end

  # 區間型的 POI 用中點定位，單點型直接用該價位。
  def bin_index_for(entry)
    price = entry[:price] || ((entry[:low] + entry[:high]) / 2.0)
    @snapshot.bin_index_for(price)
  end

  def volume_node_entries(parser)
    poc = parser.poc_bin
    entries = []
    entries << { price: poc.mid, label: "POC #{fmt(poc.mid)}", tip: "poi_poc" } if poc

    parser.merged_zones(:hvn).each do |z|
      entries << { low: z[:low], high: z[:high], tip: "poi_hvn",
                   label: "HVN #{fmt(z[:low])}–#{fmt(z[:high])}" }
    end
    parser.merged_zones(:lvn).each do |z|
      entries << { low: z[:low], high: z[:high], tip: "poi_lvn",
                   label: "LVN #{fmt(z[:low])}–#{fmt(z[:high])}" }
    end
    entries
  end

  # kind => [顯示用中文, tooltips.js 的 data-tip-key]
  STRUCT_LABELS = {
    fvg:         [ "FVG",         "poi_fvg" ],
    gap:         [ "缺口",         "poi_gap" ],
    order_block: [ "Order Block", "poi_order_block" ],
    demand:      [ "需求區",       "poi_demand" ],
    supply:      [ "供給區",       "poi_supply" ]
  }.freeze

  def structural_entries
    bars = DailyBar.lookback(@symbol)
    return [] if bars.empty?

    StructuralPoiService.new(bars).call.map do |poi|
      name, tip = STRUCT_LABELS.fetch(poi.kind, [ poi.kind.to_s, nil ])
      { low: poi.low, high: poi.high, tip: tip,
        label: "#{name} #{fmt(poi.low)}–#{fmt(poi.high)}" }
    end
  end

  # 使用者輸入的履約價一定入列（那是他這次查詢的主角），
  # 即使它的 OI 排不進前幾名。
  def option_strike_entries
    # **依履約價彙總，不是取 OI 前 N 列**。同一個履約價在多個到期日各有一列，
    # 直接 order(open_interest: :desc).limit(3) 會拿到同一個履約價的三個到期日，
    # 標籤變成「100 履約 · OI 2643 / 100 履約 · OI 1765 / 100 履約 · OI 278」——
    # 實測踩到。交易者關心的是「這個價位總共壓了多少倉」，跨到期日相加才對。
    totals = LeapsOptionChainSnapshot.for_symbol(@symbol).calls
                                     .where.not(open_interest: nil)
                                     .group(:strike).sum(:open_interest)

    ranked  = totals.sort_by { |_, oi| -oi }
    max_oi  = ranked.first&.last.to_i
    top     = ranked.first(TOP_OI_STRIKES)
                    .select { |_, oi| max_oi.positive? && oi >= max_oi * MIN_OI_RATIO_OF_TOP }

    entries = top.map do |strike, oi|
      { price: strike.to_f, tip: "poi_strike", label: "#{fmt(strike)} 履約 · OI #{oi}" }
    end

    # 使用者輸入的履約價一定入列（那是他這次查詢的主角），即使 OI 排不進前幾名。
    if @user_strike && top.none? { |strike, _| strike.to_f == @user_strike }
      entries << { price: @user_strike, tip: "poi_strike",
                   label: "#{fmt(@user_strike)} 履約（本次查詢）" }
    end
    entries
  end

  def moving_average_entries
    ta = TechnicalAnalysis.where(symbol: @symbol).order(:snapshot_date).last
    return [] if ta.nil?

    MA_LABELS.filter_map do |field, label|
      value = ta.public_send(field)
      next if value.blank? || value.to_f <= 0
      { price: value.to_f, tip: "poi_ma", label: "#{label} #{fmt(value)}" }
    end
  end

  def fmt(value) = format("%.2f", value.to_f)
end
