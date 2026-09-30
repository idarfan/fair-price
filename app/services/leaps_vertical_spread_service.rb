# frozen_string_literal: true

# LEAPS 垂直價差（bull call spread）計算（leaps-call-spread-spec P2）。
#
# 買入腳 K_L 就是使用者輸入的價格；賣出腳 K_S 必須在同一到期日且 K_S > max(K_L, 現價)。
# **所有公式只寫在這裡**，前端不做任何計算；數值全程 BigDecimal，只在 Format 顯示時四捨五入。
# chain 只透過 LeapsCallChainFetcher 取得。
class LeapsVerticalSpreadService
  TARGET_DELTA = BigDecimal("0.30")          # 賣腳預設：delta 最接近 0.30
  DELTA_TOLERANCE = BigDecimal("0.05")       # 選中的賣腳 |Δ − 0.30| 超過這個值就提示偏離（tasks/leaps-vertical-fix.md S4）
  NO_DELTA_SPOT_MULTIPLIER = BigDecimal("1.3") # 沒有 delta 時：履約價最接近 現價 × 1.3
  CONTRACT_MULTIPLIER = 100
  FETCH_FAILURE_CODES = %i[stalled fetch_failed session_expired].freeze

  CONTRACTS_FORMAT = /\A[1-9]\d*\z/ # 口數：只接受正整數（tasks/leaps-vertical-fix.md S3 第 8 點）

  def initialize(ticker:, long_strike:, expiry: nil, short_strike: nil, contracts: nil, fetcher: nil)
    @symbol = LeapsCallChainFetcher.normalize(ticker)
    @long_strike_raw = long_strike.to_s.strip
    @expiry = expiry.presence
    @short_strike_raw = short_strike.to_s.strip.presence
    @contracts_raw = contracts.to_s.strip.presence || "1"
    @fetcher = fetcher
  end

  # 標的或價格任一沒有輸入：不查詢，回 nil（頁面不渲染本區塊）。
  def call
    return nil if @symbol.blank? || @long_strike_raw.blank?

    k_l = parse_strike(@long_strike_raw)
    return failure(:invalid_input, "價格格式錯誤：#{@long_strike_raw}") unless k_l

    chain = fetcher.call(**(@expiry ? { only_expiry: @expiry } : {}))
    return fetch_failure(chain) unless chain[:status] == :ok

    build(chain, k_l)
  end

  private

  def fetcher = @fetcher ||= LeapsCallChainFetcher.new(@symbol)

  def build(chain, k_l)
    @spot = chain[:spot]
    long_options = long_options_for(chain, k_l)
    return failure(:strike_not_found, strike_not_found_message(chain, k_l)) if long_options.empty?

    # 現價取自最新一次爬取的 chain（LeapsCallChainFetcher#build_result），它的爬取時間用來判斷 stale_quote。
    @spot_quoted_at = chain[:expirations].filter_map { |e| e[:fetched_at] }.max
    base = { symbol: @symbol, long_strike: k_l, spot: @spot, long_options: long_options, contracts: @contracts_raw }
    if long_options.all? { |o| o[:disabled] }
      return base.merge(failure(:no_quote, "履約價 #{Format.num(k_l)} 在所有 LEAPS 到期日都沒有有效報價"))
    end

    long = select_long(long_options, k_l)
    expiry_data = chain[:expirations].find { |e| e[:expiry] == long[:expiry] }
    short_options = short_options_for(expiry_data, k_l)
    @quoted_at = expiry_data[:fetched_at]
    base = base.merge(short_options: short_options, quoted_at: @quoted_at)
    finish(base, long, expiry_data, short_options, k_l)
  end

  def finish(base, long, expiry_data, short_options, k_l)
    default = default_short(short_options, long, k_l)
    short = requested_short(expiry_data) || default
    selected = { expiry: long[:expiry], short_strike: short&.dig(:strike), default_short_strike: default&.dig(:strike) }
    base = base.merge(legs: { long: long, short: short })
    return base.merge(selected: selected).merge(failure(:no_short, "#{long[:expiry][0, 10]} 沒有符合條件的價外賣出腳")) unless short

    invalid = invalid_reason(long, short, k_l)
    return base.merge(selected: selected).merge(failure(:invalid_combo, invalid)) if invalid
    unless @contracts_raw.match?(CONTRACTS_FORMAT)
      return base.merge(selected: selected).merge(failure(:invalid_input, "口數須為正整數：#{@contracts_raw}"))
    end

    base.merge(selected: selected, result: compute(long, short, k_l), error: nil)
  end

  # ── 報價規則：bid、ask 皆 > 0 → mid；否則 last > 0 → last（盤後參考價）；否則無報價 ──
  def priced(quote)
    price, source = if positive?(quote[:bid]) && positive?(quote[:ask])
      [ (quote[:bid] + quote[:ask]) / 2, :mid ]
    elsif positive?(quote[:last])
      [ quote[:last], :last ]
    end
    quote.merge(price: price, source: source, disabled: price.nil?)
  end

  def long_options_for(chain, k_l)
    chain[:expirations].filter_map do |e|
      quote = e[:calls].find { |c| c[:strike].round(2) == k_l }
      next unless quote

      option = priced(quote).merge(expiry: e[:expiry], dte: e[:dte])
      option.merge(label: Format.long_label(option))
    end.sort_by { |o| o[:dte] }
  end

  def short_options_for(expiry_data, k_l)
    floor = [ k_l, @spot ].compact.max
    expiry_data[:calls].select { |c| c[:strike] > floor }.sort_by { |c| c[:strike] }.map do |quote|
      option = priced(quote)
      option.merge(label: Format.short_label(option))
    end
  end

  # ── 預設值（功能定義 2）──
  def select_long(options, k_l)
    enabled = options.reject { |o| o[:disabled] }
    enabled.find { |o| o[:expiry] == @expiry } ||
      enabled.find { |o| o[:expiry][0, 10] == ranked_expiry_date(k_l)&.iso8601 } ||
      enabled.max_by { |o| o[:dte] }
  end

  # LEAPS Call 候選排行中履約價等於 K_L 的第 1 名（排行已依 OI、DTE 排好）。
  def ranked_expiry_date(k_l)
    top = LeapsRankingService.new(@symbol).call.find { |c| c[:snapshot].strike.round(2) == k_l }
    top&.dig(:snapshot)&.expiration_date
  end

  def default_short(short_options, long, k_l)
    qualifying = short_options.reject { |o| o[:disabled] }.select do |o|
      d_mid = long[:price] - o[:price]
      d_mid.positive? && d_mid < o[:strike] - k_l
    end
    return nil if qualifying.empty?

    with_delta = qualifying.reject { |o| o[:delta].nil? }
    return with_delta.min_by { |o| [ (o[:delta] - TARGET_DELTA).abs, o[:strike] ] } if with_delta.any?

    target = @spot * NO_DELTA_SPOT_MULTIPLIER
    qualifying.min_by { |o| [ (o[:strike] - target).abs, o[:strike] ] }
  end

  def requested_short(expiry_data)
    k_s = @short_strike_raw && parse_strike(@short_strike_raw)
    quote = k_s && expiry_data[:calls].find { |c| c[:strike].round(2) == k_s }
    quote && priced(quote)
  end

  # ── 無效組合：說明是哪一個條件不成立 ──
  def invalid_reason(long, short, k_l)
    k_s = short[:strike]
    return "賣出腳履約價 #{Format.num(k_s)} 必須高於買入腳履約價 #{Format.num(k_l)}" if k_s <= k_l
    return "賣出腳履約價 #{Format.num(k_s)} 必須高於現價 #{Format.num(@spot)}（價外）" if @spot && k_s <= @spot
    return "賣出腳 #{Format.num(k_s)} #{Format::NO_QUOTE}" if short[:disabled]

    width = k_s - k_l
    d_mid = long[:price] - short[:price]
    return "淨成本 #{Format.num(d_mid)} ≤ 0，報價異常" unless d_mid.positive?
    return "淨成本 #{Format.num(d_mid)} ≥ 價差寬度 #{Format.num(width)}，沒有獲利空間" if d_mid >= width

    nil
  end

  # ── 公式（每口，乘數 100）──
  def compute(long, short, k_l)
    width = short[:strike] - k_l
    d_mid = long[:price] - short[:price]
    both_quoted = long[:source] == :mid && short[:source] == :mid
    d_nat = both_quoted ? long[:ask] - short[:bid] : nil

    values = {
      width: width, d_mid: d_mid, d_nat: d_nat,
      net_cost: d_mid * CONTRACT_MULTIPLIER,
      net_cost_nat: d_nat && d_nat * CONTRACT_MULTIPLIER,
      max_loss: d_mid * CONTRACT_MULTIPLIER,
      max_profit: (width - d_mid) * CONTRACT_MULTIPLIER,
      breakeven: k_l + d_mid,
      risk_reward: (width - d_mid) / d_mid,
      after_hours_legs: [ (:long if long[:source] == :last), (:short if short[:source] == :last) ].compact
    }.merge(explanation_values(long, short, k_l, d_mid)).merge(spread_values(long, short))
    values.merge(display: Format.result(values), cards: Format.cards(values[:metrics]))
  end

  # ── S1～S3：雙基準指標（含口數、費用）與平倉計算需要的參數（tasks/leaps-vertical-fix.md）──
  # display／既有欄位維持「每口、不含費用」，供 Explanation 的算式使用；卡片數字改用 metrics。
  def spread_values(long, short)
    contracts = @contracts_raw.to_i
    fee = Config.fee_per_contract_leg
    legs = { long: quote_leg(long), short: quote_leg(short) }
    close_out = @spot && CloseOut.new(**legs, spot: @spot, quote_date: quote_date,
                                      expiry: Date.parse(long[:expiry][0, 10]), contracts: contracts,
                                      fee_per_leg: fee, dividend_annual: dividend_annual,
                                      spot_quoted_at: @spot_quoted_at, option_quoted_at: @quoted_at)
    {
      contracts: contracts, fee_per_leg: fee, delta_deviation: delta_deviation(short),
      metrics: Metrics.dual(**legs, contracts: contracts, fee_per_leg: fee),
      ivs: close_out&.ivs, close_out_error: close_out ? close_out.error : CloseOut::IV_FAILURE,
      flags: close_out&.quote_flags || {},
      payoff_params: close_out && payoff_params(legs, long, contracts)
    }
  end

  # 選中的賣腳偏離建議 Δ 時回傳它的 Δ（S4 第 2 點）；沒有 Δ 資料時無從判斷，不提示。
  def delta_deviation(short)
    delta = short[:delta]
    delta if delta && (delta - TARGET_DELTA).abs > DELTA_TOLERANCE
  end

  # 兩腳都有買賣價才帶 bid／ask（盤後以 last 為價的腳沒有保守基準，與 compute 的 d_nat 一致）。
  def quote_leg(leg)
    both_quoted = leg[:source] == :mid
    { strike: leg[:strike], price: leg[:price], **(both_quoted ? leg.slice(:bid, :ask) : {}) }
  end

  # 報價日以美東日期計（到期日是美股日期）；T = 日曆天數 ÷ 365。
  def quote_date = (@quoted_at || Time.current).in_time_zone("America/New_York").to_date

  # 股息：fundamentals.dividend_annual（Barchart 前瞻年股息）；沒有資料 → nil → CloseOut 回 dividend_unknown。
  def dividend_annual
    @dividend_annual ||= [ Fundamental.where(symbol: @symbol).order(snapshot_date: :desc).pick(:dividend_annual) ]
    @dividend_annual.first
  end

  # 預估股價片段（payoff=1）要帶回伺服器的參數：BigDecimal 原值，不經顯示四捨五入。
  def payoff_params(legs, long, contracts)
    leg_params = legs.flat_map { |side, leg| leg.map { |k, v| [ :"#{side}_#{k}", v.to_s("F") ] } }.to_h
    leg_params.merge(
      spot: @spot.to_s("F"), quote_date: quote_date.iso8601, expiry: long[:expiry][0, 10],
      dividend_annual: dividend_annual&.to_s("F"), contracts: contracts.to_s,
      spot_quoted_at: @spot_quoted_at&.utc&.iso8601, option_quoted_at: @quoted_at&.utc&.iso8601
    ).compact
  end

  # P6 說明用的衍生值（公式只寫在這個 service）。
  def explanation_values(long, short, k_l, d_mid)
    intrinsic = @spot ? [ @spot - short[:strike], BigDecimal("0") ].max : BigDecimal("0")
    {
      short_extrinsic:   short[:price] - intrinsic,
      breakeven_vs_spot: @spot && (k_l + d_mid - @spot) / @spot,
      short_vs_spot:     @spot && (short[:strike] - @spot) / @spot,
      premium_recovery:  short[:price] / long[:price],
      no_delta_target:   @spot && @spot * NO_DELTA_SPOT_MULTIPLIER
    }
  end

  # ── 錯誤（功能定義 6）──
  def strike_not_found_message(chain, k_l)
    strikes = chain[:expirations].flat_map { |e| e[:calls].map { |c| c[:strike] } }.uniq
    nearest = [ strikes.select { |s| s < k_l }.max, strikes.select { |s| s > k_l }.min ].compact
    "#{@symbol} 的 LEAPS 中查無履約價 #{Format.num(k_l)}；最接近的履約價：#{nearest.map { |s| Format.num(s) }.join('、')}"
  end

  def fetch_failure(chain)
    if FETCH_FAILURE_CODES.include?(chain[:code])
      failure(:fetch_failed, "Barchart 讀取失敗：#{chain[:message]}", retryable: true)
    else
      failure(chain[:code], chain[:message])
    end
  end

  def failure(kind, message, retryable: false)
    { symbol: @symbol, result: nil, error: { kind: kind, message: message, retryable: retryable } }
  end

  def parse_strike(raw)
    value = BigDecimal(raw.to_s)
    value.positive? ? value.round(2) : nil
  rescue ArgumentError, TypeError
    nil
  end

  def positive?(value) = !value.nil? && value.positive?
end
