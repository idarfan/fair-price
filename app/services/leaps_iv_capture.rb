# frozen_string_literal: true

# LEAPS IV 環境的原始資料寫入（leaps-iv-environment.md P2）。只存原始資料：
# cm540_atm_iv 由 LeapsIvEnvironmentService#persist!（P3）計算寫入，這裡不算。
#
# 兩個來源：
#   - LEAPS 爬蟲的 Stage 3（iv_surface）→ leaps_iv_snapshots 的現價＋leaps_iv_surface_points
#   - Barchart Options Overview History 爬蟲 → barchart_iv_histories＋leaps_iv_snapshots 的 HV
# 一律 upsert，後寫覆蓋先寫。兩個來源各自只更新自己負責的欄位，彼此不互相洗掉。
#
# as_of_date 取頁面報價日期（MM/DD/YY，Barchart 頁首顯示的美東交易日）；讀不到就整筆失敗，
# 不得用系統時間代替（規格「名詞與公式」）。
class LeapsIvCapture
  class CaptureError < StandardError; end

  MONEYNESS_RANGE = (0.60..1.25) # 曲面顯示範圍（P3 surface 讀取時篩）；寫入時不篩
  HV_LABEL        = "HV 30 天" # overview 頁標籤沒有天數，依名詞說明「30-Day Historical Volatility」（使用者裁示）

  def initialize(symbol, source:)
    @symbol = symbol.to_s.upcase
    @source = source.to_s
    raise ArgumentError, "source 必須是 #{LeapsIvSnapshot::SOURCES.join('／')}" unless LeapsIvSnapshot::SOURCES.include?(@source)
  end

  # LEAPS 爬蟲成功結果 → 快照（現價）＋曲面點。回傳寫入的曲面點數。
  def persist_leaps_chain(data)
    # 現價取頁首 pricechangerow 的收盤價（quote_last），與 as_of_date 同一個區塊讀出，一定配對。
    # 不用 underlying_price：它在 pricechangerow 不存在時會退回別的讀法，可能讀到盤前即時價
    # （2026-11-06 P4 實跑 NOK：寫成「11/05 的日期＋11/06 盤前 7.82」）。
    spot = data["quote_last"].to_f
    raise CaptureError, "讀不到頁面收盤價（pricechangerow）" unless spot.positive?

    as_of_date = self.class.as_of_date(data["quote_date_text"])
    now        = Time.current
    points     = surface_points(data["iv_surface"], spot, as_of_date, now)
    raise CaptureError, "IV 曲面沒有任何點（#{data['iv_surface_error']}）" if points.empty?

    ActiveRecord::Base.transaction do
      LeapsIvSnapshot.upsert(
        { symbol: @symbol, as_of_date: as_of_date, spot: spot, source: @source,
          captured_at: now, source_url: data.fetch("source_url") },
        unique_by: %i[symbol as_of_date], update_only: %i[spot source captured_at source_url]
      )
      # 當天整張曲面以最後一次抓取為準（後寫覆蓋先寫）：只 upsert 的話，上一次有、這次沒抓到的
      # 到期日／履約價會留在表裡，CM540 會被過期的點夾住（P3 r1 質詢 2 的測試抓到）。
      # 例外：爬蟲回報「重試後仍沒載入」的到期日（iv_surface_missing）保留舊點——那是這次抓取不完整，
      # 不是到期日消失；整批刪掉會讓一次不完整的抓取蓋掉完整資料（P4 實跑 TSM 115 點掉到 69 點）。
      LeapsIvSurfacePoint.where(symbol: @symbol, as_of_date: as_of_date)
                         .where.not(expiration: missing_expirations(data))
                         .delete_all
      LeapsIvSurfacePoint.insert_all(points)
    end
    points.size
  end

  # Barchart 歷史表爬蟲結果 → barchart_iv_histories＋快照的 HV。回傳寫入的歷史列數。
  def persist_barchart_history(data)
    now  = Time.current
    rows = Array(data["rows"]).map { |raw| history_row(raw, now, data.fetch("source_url")) }
    raise CaptureError, "Options Overview History 沒有任何列" if rows.empty?

    hv = data["hv_pct"]
    raise CaptureError, "overview 頁讀不到 Historical Volatility" unless hv.is_a?(Numeric) && hv.positive?

    as_of_date = self.class.as_of_date(data["quote_date_text"])
    ActiveRecord::Base.transaction do
      BarchartIvHistory.upsert_all(rows, unique_by: %i[symbol trade_date])
      LeapsIvSnapshot.upsert(
        { symbol: @symbol, as_of_date: as_of_date, bc_hv: (hv.to_d / 100).round(5), bc_hv_label: HV_LABEL,
          source: @source, captured_at: now, source_url: data.fetch("hv_source_url") },
        unique_by: %i[symbol as_of_date], update_only: %i[bc_hv bc_hv_label]
      )
    end
    rows.size
  end

  # 美股正常交易時段不寫入任何 IV 環境資料（2026-11-06 使用者裁示）：盤中頁首的
  # div.pricechangerow 帶 data-ng-if="session !== 'Realtime'"，讀不到收盤報價日期，
  # 期權 IV 也在變動。定義與 StockPriceChecker#market_open? 相同（美東週一～五 09:30–16:00）：
  # 只排除週末，美股假日的同一時段也視為盤中而不寫入——假日不會產生新的交易日，結果安全，
  # 下一次非盤中查詢或排程會補上。呼叫端（BarchartScraperService）據此略過。
  def self.regular_session?(time = Time.current)
    et = time.in_time_zone("Eastern Time (US & Canada)")
    return false if et.saturday? || et.sunday?

    et.between?(et.change(hour: 9, min: 30), et.change(hour: 16, min: 0))
  end

  def self.as_of_date(text)
    raise CaptureError, "讀不到頁面報價日期" if text.blank?

    Date.strptime(text.to_s.strip, "%m/%d/%y")
  rescue Date::Error
    raise CaptureError, "頁面報價日期格式無法辨識：#{text.inspect}"
  end

  def self.missing_expirations(data)
    Array(data["iv_surface_missing"]).map { |d| Date.parse(d.to_s) }
  end

  private

  def missing_expirations(data) = self.class.missing_expirations(data)

  def surface_points(raw_rows, spot, as_of_date, now)
    Array(raw_rows).filter_map do |r|
      strike = r["strike"]&.to_d
      next if strike.nil? || r["expiration_date"].blank?

      # 全部履約價都存，不在這裡篩 moneyness（2026-11-06 使用者裁示，P4 實跑發現）：ATM IV 要用
      # 「夾住現價的上下兩檔」，履約價間距大的低價股（NOK 現價 7.46，上一檔是 10＝1.34）上方那檔常在
      # 0.60–1.25 之外，存入時先篩掉就算不出 ATM 與 CM540。0.60–1.25 只在 P3 讀曲面時篩。
      moneyness = (strike / spot.to_d).round(4)

      { symbol: @symbol, as_of_date: as_of_date, expiration: Date.parse(r["expiration_date"]),
        dte: r["dte"], strike: strike, moneyness: moneyness,
        call_iv: r["iv"]&.to_d&.round(5), delta: r["delta"]&.to_d&.round(4), captured_at: now }
    end.uniq { |p| [ p[:expiration], p[:strike] ] }
  end

  # 單位：IV 小數；IV Rank 頁面已是 0–100；IV Pctl 頁面是小數（P0 偵察 0.9243），×100。
  def history_row(raw, now, source_url)
    pctl = raw["impliedVolatilityPercentile1y"]&.to_d
    pctl = (pctl * 100).round(2) if pctl
    rank = raw["impliedVolatilityRank1y"]&.to_d&.round(2)
    [ [ "IV Rank", rank ], [ "IV Pctl", pctl ] ].each do |name, v|
      raise CaptureError, "#{raw['date']} 的 #{name} #{v} 超出 0–100" if v && !(0..100).cover?(v)
    end

    { symbol: @symbol, trade_date: Date.parse(raw.fetch("date")),
      imp_vol: raw["weightedImpliedVolatility"]&.to_d&.round(5), iv_rank: rank, iv_pctl: pctl,
      pc_vol_ratio: raw["putCallVolumeRatio"]&.to_d&.round(4), options_volume: raw["totalVolume"],
      pc_oi_ratio: raw["putCallOpenInterestRatio"]&.to_d&.round(4), total_oi: raw["totalOpenInterest"],
      last_price: raw["historicalLastPrice"]&.to_d&.round(4), captured_at: now, source_url: source_url }
  end
end
