# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 預估股價 → 平倉理論損益＋到期損益（leaps-call-spread-spec P7；tasks/leaps-vertical-fix.md S3）。
  #
  # 到期損益走 Metrics（mid 基準、含口數與費用）；平倉理論損益走 CloseOut（BS，平倉日預設報價日）。
  # 兩腳報價、日期、口數由區塊渲染時從 service 結果帶到頁面上（data-vs-payoff-params），前端原樣帶回；
  # 這裡全部重新驗證，只重算、不抓 Barchart。費率一律讀設定檔，不信任前端。
  module Payoff
    IV_SHIFT_RANGE = BigDecimal("-50")..BigDecimal("50")
    PARAMS_ERROR = "價差參數不合法，請重新整理區塊"
    INTEGER_FORMAT = /\A[1-9]\d*\z/

    module_function

    # 預估價空白回 nil；任何參數不合法回 { error: }。
    def call(params)
      raw_target = params[:target_price].to_s.strip
      return nil if raw_target.empty?

      # 預估價可以是 0（標的歸零）；BigDecimal 會把 "NaN"／"Infinity" 解析成功，要另外擋。
      target = decimal(raw_target)
      return { error: "預估股價格式錯誤：#{raw_target}" } unless target&.finite? && !target.negative?

      # 空白才算 0；打錯字不能悄悄變成 0。
      iv_shift = params[:iv_shift].to_s.strip.empty? ? BigDecimal("0") : decimal(params[:iv_shift])
      return { error: "IV 調整須介於 −50 與 +50（百分點）" } unless iv_shift&.finite? && IV_SHIFT_RANGE.cover?(iv_shift)

      spread = spread_from(params)
      return { error: PARAMS_ERROR } unless spread

      close_date = params[:close_date].to_s.strip.empty? ? spread[:quote_date] : date(params[:close_date])
      return { error: "平倉日格式錯誤：#{params[:close_date]}" } unless close_date

      result(spread, target, close_date, iv_shift)
    end

    def result(spread, target, close_date, iv_shift)
      mid = Metrics.dual(long: spread[:long], short: spread[:short], contracts: spread[:contracts],
                         fee_per_leg: Config.fee_per_contract_leg, target_price: target)[:mid]
      close = CloseOut.new(**spread.except(:contracts), contracts: spread[:contracts])
                      .call(price: target, date: close_date, iv_shift: iv_shift)
      { expiry: expiry_result(mid[:payoff]), close: close_result(close), flags: close[:flags] || {} }
    end

    def expiry_result(payoff)
      pnl = payoff[:pnl]
      { pnl: pnl, return_ratio: payoff[:return_ratio], tone: tone(pnl),
        display: { pnl: signed_money(pnl), pct: Format.pct(payoff[:return_ratio]) } }
    end

    def close_result(close)
      return { error: close[:error] } if close[:error]

      conservative = close[:pnl_conservative]
      { pnl: close[:pnl], pnl_conservative: conservative, tone: tone(close[:pnl]),
        display: { pnl: signed_money(close[:pnl]), conservative: conservative ? signed_money(conservative) : "—" } }
    end

    # ── 參數：區塊渲染時由 LeapsVerticalSpreadService#payoff_params 產生 ──
    OPTIONAL_DECIMALS = %i[long_bid long_ask short_bid short_ask dividend_annual].freeze
    OPTIONAL_TIMES = %i[spot_quoted_at option_quoted_at].freeze

    def spread_from(params)
      # 選填欄位可以空白，但有值就必須解析得出來，不能悄悄當成「沒有」。
      return nil unless OPTIONAL_DECIMALS.all? { |k| blank?(params[k]) || decimal(params[k])&.finite? } &&
                        OPTIONAL_TIMES.all? { |k| blank?(params[k]) || time(params[k]) }

      long = leg(params, :long)
      short = leg(params, :short)
      spot = positive(params[:spot])
      contracts = params[:contracts].to_s.strip.match?(INTEGER_FORMAT) ? params[:contracts].to_i : nil
      quote_date, expiry = date(params[:quote_date]), date(params[:expiry])
      return nil unless long && short && spot && contracts && quote_date && expiry && valid_legs?(long, short)

      dividend = optional_decimal(params[:dividend_annual])
      return nil if dividend && (!dividend.finite? || dividend.negative?)

      { long: long, short: short, spot: spot, contracts: contracts, quote_date: quote_date, expiry: expiry,
        dividend_annual: dividend, spot_quoted_at: time(params[:spot_quoted_at]),
        option_quoted_at: time(params[:option_quoted_at]) }
    end

    # bid／ask 只有在兩個都有值時才帶（盤後以 last 為價的腳沒有保守基準）。
    def leg(params, side)
      strike = positive(params[:"#{side}_strike"])
      price = positive(params[:"#{side}_price"])
      return nil unless strike && price

      bid, ask = optional_decimal(params[:"#{side}_bid"]), optional_decimal(params[:"#{side}_ask"])
      quoted = bid&.finite? && ask&.finite? && !bid.negative? && ask >= bid
      { strike: strike, price: price, **(quoted ? { bid: bid, ask: ask } : {}) }
    end

    def valid_legs?(long, short)
      d_mid = long[:price] - short[:price]
      short[:strike] > long[:strike] && d_mid.positive? && d_mid < short[:strike] - long[:strike]
    end

    def tone(pnl)
      return :profit if pnl.positive?

      pnl.negative? ? :loss : :breakeven
    end

    def signed_money(value) = value.positive? ? "+#{Format.money(value)}" : Format.money(value)

    def positive(raw)
      value = decimal(raw)
      value&.finite? && value.positive? ? value : nil
    end

    def blank?(raw) = raw.to_s.strip.empty?
    def optional_decimal(raw) = blank?(raw) ? nil : decimal(raw)

    def decimal(raw)
      BigDecimal(raw.to_s.strip)
    rescue ArgumentError, TypeError
      nil
    end

    def date(raw)
      Date.iso8601(raw.to_s.strip)
    rescue Date::Error
      nil
    end

    def time(raw)
      raw.to_s.strip.empty? ? nil : Time.iso8601(raw.to_s.strip)
    rescue ArgumentError
      nil
    end
  end
end
