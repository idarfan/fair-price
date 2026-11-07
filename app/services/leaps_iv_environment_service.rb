# frozen_string_literal: true

# LEAPS IV 環境計算（leaps-iv-environment.md P3）。公式唯一定義在規格「名詞與公式」章節，這裡照實作：
#
#   ATM IV（單一到期日）：夾住現價 S 的上下兩檔 call IV，依履約價線性內插；S 恰為履約價取該檔；
#                        S 不在任何兩檔之間記 nil。
#   CM540：夾住 540 天的相鄰兩到期日，以總變異數 w = σ²T（T＝DTE/365）對 T 線性內插，σ = sqrt(w/T)；
#          夾不住（或其中一個到期日算不出 ATM IV）記 nil，不外插。
#   IV Rank／Percentile：指標固定為 CM540；期間＝as_of_date 早於當日且在 365 個日曆天內的快照（最多 252 筆），
#          歷史筆數 n < min_history 時兩者皆 nil、status :accumulating；最高等於最低時 Rank nil。
#
# Barchart 的 IV Rank／Pctl 直接採用頁面值（barchart_iv_histories），不重算。
# persist! 是寫入 cm540_atm_iv 的唯一入口（P2 抓取完成後呼叫）。
class LeapsIvEnvironmentService
  TARGET_DTE        = 540
  DAYS_PER_YEAR     = 365.0
  LOOKBACK_DAYS     = 365
  MAX_HISTORY       = 252
  BARCHART_HISTORY  = 252
  CM540_SCALE       = 5 # 同 leaps_iv_snapshots.cm540_atm_iv decimal(8,5)
  # PMCC 短天期鏈每次查詢整批覆蓋、沒有歷史：只有和快照同一次抓取（scraped_at 與 captured_at
  # 相差在這個時間內）才併進曲面，避免把別的時間點的短天期 IV 混進來（P2 r2 質詢 2）。
  PMCC_ALIGN_WINDOW = LeapsOptionChainSnapshot::FRESH_WINDOW

  def initialize(min_history: 20)
    @min_history = min_history
  end

  def call(symbol:, as_of_date: nil)
    symbol   = symbol.to_s.upcase
    snapshot = find_snapshot(symbol, as_of_date)
    return no_data(as_of_date) unless snapshot

    chain   = chain_points(symbol, snapshot)
    term    = term_structure(chain, snapshot)
    cm540   = cm540_for(term)
    history = rank_history(symbol, snapshot.as_of_date)
    enough  = history.size >= @min_history

    {
      as_of_date:     snapshot.as_of_date,
      cm540:          cm540,
      rank:           enough && cm540 ? self.class.iv_rank(history, cm540) : nil,
      percentile:     enough && cm540 ? self.class.iv_percentile(history, cm540) : nil,
      history_count:  history.size,
      status:         enough ? :ok : :accumulating,
      term_structure: term,
      surface:        surface(chain, snapshot),
      barchart:       barchart(symbol, snapshot)
    }
  end

  # 計算 cm540 寫回快照；回傳寫入的值（夾不住為 nil，也照寫 nil）。
  def persist!(symbol:, as_of_date:)
    symbol   = symbol.to_s.upcase
    snapshot = LeapsIvSnapshot.find_by!(symbol: symbol, as_of_date: as_of_date)
    cm540    = cm540_for(term_structure(chain_points(symbol, snapshot), snapshot))
    snapshot.update!(cm540_atm_iv: cm540)
    cm540
  end

  # ── 公式（規格「名詞與公式」；測試向量直接打這幾個方法）────────────────────

  # points: [[strike, iv], ...]；回傳 S 處的 ATM IV 或 nil
  def self.atm_iv(points, spot)
    pts = points.reject { |_, iv| iv.nil? }.sort_by(&:first)
    exact = pts.find { |k, _| k == spot }
    return exact.last.to_f if exact

    lower = pts.select { |k, _| k < spot }.last
    upper = pts.find { |k, _| k > spot }
    return nil unless lower && upper

    (k1, iv1), (k2, iv2) = lower, upper
    iv1.to_f + ((spot - k1) / (k2 - k1)) * (iv2.to_f - iv1.to_f)
  end

  # points: [[T, σ], ...]（σ 可為 nil，表示該到期日算不出 ATM IV）；target_t 以年為單位
  def self.constant_maturity_iv(points, target_t)
    pts = points.sort_by(&:first)
    exact = pts.find { |t, _| t == target_t }
    return exact.last&.to_f if exact

    lower = pts.select { |t, _| t < target_t }.last
    upper = pts.find { |t, _| t > target_t }
    return nil unless lower && upper && lower.last && upper.last

    (t1, s1), (t2, s2) = lower, upper
    w1 = s1.to_f**2 * t1
    w2 = s2.to_f**2 * t2
    w  = w1 + ((target_t - t1) / (t2 - t1)) * (w2 - w1)
    Math.sqrt(w / target_t)
  end

  def self.iv_rank(history, current)
    lo, hi = history.minmax
    return nil if hi == lo

    (current - lo) / (hi - lo) * 100
  end

  def self.iv_percentile(history, current)
    history.count { |v| v < current } * 100.0 / history.size
  end

  private

  def no_data(as_of_date)
    { as_of_date: as_of_date, cm540: nil, rank: nil, percentile: nil, history_count: 0, status: :no_data,
      term_structure: [], surface: [], barchart: nil }
  end

  def find_snapshot(symbol, as_of_date)
    scope = LeapsIvSnapshot.where(symbol: symbol)
    as_of_date ? scope.find_by(as_of_date: as_of_date) : scope.order(as_of_date: :desc).first
  end

  # 期間內（早於當日、365 個日曆天內）的 cm540，最近 252 筆
  def rank_history(symbol, as_of_date)
    LeapsIvSnapshot.where(symbol: symbol)
                   .where(as_of_date: (as_of_date - LOOKBACK_DAYS + 1)...as_of_date)
                   .where.not(cm540_atm_iv: nil)
                   .order(as_of_date: :desc).limit(MAX_HISTORY)
                   .pluck(:cm540_atm_iv).map(&:to_f)
  end

  # LEAPS 曲面點（當天）＋同一次抓取的 PMCC 短天期點，依到期日分組
  def chain_points(symbol, snapshot)
    leaps = LeapsIvSurfacePoint.where(symbol: symbol, as_of_date: snapshot.as_of_date)
                               .pluck(:expiration, :dte, :strike, :call_iv)
    leaps + pmcc_points(symbol, snapshot)
  end

  def pmcc_points(symbol, snapshot)
    return [] unless snapshot.spot

    window = (snapshot.captured_at - PMCC_ALIGN_WINDOW)..(snapshot.captured_at + PMCC_ALIGN_WINDOW)
    PmccShortCallSnapshot.where(symbol: symbol, option_type: "Call", scraped_at: window)
                         .where.not(iv: nil).where("dte > 0")
                         .pluck(:expiration_date, :dte, :strike, :iv)
  end

  def term_structure(chain, snapshot)
    chain.group_by { |exp, dte, _, _| [ exp, dte ] }.map do |(exp, dte), rows|
      atm = snapshot.spot && self.class.atm_iv(rows.map { |_, _, k, iv| [ k.to_f, iv&.to_f ] }, snapshot.spot.to_f)
      { expiration: exp, dte: dte, atm_iv: atm }
    end.sort_by { |p| p[:dte] }
  end

  # 捨入到與 cm540_atm_iv 欄位相同的 5 位：call 的現值、persist! 寫入的值、Rank／Percentile 期間內的
  # 歷史值三者同一精度，邊界上不會因精度不同差一筆（P3 r1 質詢 1）。
  def cm540_for(term)
    self.class.constant_maturity_iv(term_points(term), TARGET_DTE / DAYS_PER_YEAR)&.round(CM540_SCALE)
  end

  def term_points(term)
    term.map { |p| [ p[:dte] / DAYS_PER_YEAR, p[:atm_iv] ] }
  end

  def surface(chain, snapshot)
    return [] unless snapshot.spot

    range = LeapsIvCapture::MONEYNESS_RANGE
    chain.filter_map do |exp, dte, strike, iv|
      m = (strike.to_d / snapshot.spot).round(4)
      { expiration: exp, dte: dte, moneyness: m.to_f, call_iv: iv&.to_f } if range.cover?(m)
    end.sort_by { |p| [ p[:dte], p[:moneyness] ] }
  end

  def barchart(symbol, snapshot)
    rows = BarchartIvHistory.where(symbol: symbol).where(trade_date: ..snapshot.as_of_date)
    latest = rows.order(trade_date: :desc).first
    return nil unless latest

    history = rows.order(trade_date: :desc).limit(BARCHART_HISTORY)
                  .pluck(:trade_date, :imp_vol, :iv_rank, :last_price).reverse
                  .map { |d, iv, rank, px| { trade_date: d, imp_vol: iv&.to_f, iv_rank: rank&.to_f, last_price: px&.to_f } }
    {
      trade_date: latest.trade_date, imp_vol: latest.imp_vol&.to_f, iv_rank: latest.iv_rank&.to_f,
      iv_pctl: latest.iv_pctl&.to_f, hv: snapshot.bc_hv&.to_f, hv_label: snapshot.bc_hv_label, history: history
    }
  end
end
