# frozen_string_literal: true

# LEAPS 垂直價差（bull call spread）計算（leaps-call-spread-spec P2）。
#
# 買入腳 K_L 就是使用者輸入的價格；賣出腳 K_S 必須在同一到期日且 K_S > max(K_L, 現價)。
# **所有公式只寫在這裡**，前端不做任何計算；數值全程 BigDecimal，只在 Format 顯示時四捨五入。
# chain 只透過 LeapsCallChainFetcher 取得。
class LeapsVerticalSpreadService
  TARGET_DELTA = BigDecimal("0.30")          # 賣腳預設：delta 最接近 0.30
  NO_DELTA_SPOT_MULTIPLIER = BigDecimal("1.3") # 沒有 delta 時：履約價最接近 現價 × 1.3
  CONTRACT_MULTIPLIER = 100
  FETCH_FAILURE_CODES = %i[stalled fetch_failed session_expired].freeze

  def initialize(ticker:, long_strike:, expiry: nil, short_strike: nil, fetcher: nil)
    @symbol = LeapsCallChainFetcher.normalize(ticker)
    @long_strike_raw = long_strike.to_s.strip
    @expiry = expiry.presence
    @short_strike_raw = short_strike.to_s.strip.presence
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

    base = { symbol: @symbol, long_strike: k_l, spot: @spot, long_options: long_options }
    if long_options.all? { |o| o[:disabled] }
      return base.merge(failure(:no_quote, "履約價 #{Format.num(k_l)} 在所有 LEAPS 到期日都沒有有效報價"))
    end

    long = select_long(long_options, k_l)
    expiry_data = chain[:expirations].find { |e| e[:expiry] == long[:expiry] }
    short_options = short_options_for(expiry_data, k_l)
    base = base.merge(short_options: short_options, quoted_at: expiry_data[:fetched_at])
    finish(base, long, expiry_data, short_options, k_l)
  end

  def finish(base, long, expiry_data, short_options, k_l)
    short = requested_short(expiry_data) || default_short(short_options, long, k_l)
    selected = { expiry: long[:expiry], short_strike: short&.dig(:strike) }
    return base.merge(selected: selected).merge(failure(:no_short, "#{long[:expiry][0, 10]} 沒有符合條件的價外賣出腳")) unless short

    invalid = invalid_reason(long, short, k_l)
    return base.merge(selected: selected).merge(failure(:invalid_combo, invalid)) if invalid

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
    }
    values.merge(display: Format.result(values))
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
