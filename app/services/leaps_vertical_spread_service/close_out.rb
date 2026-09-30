# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 指定日平倉理論損益（tasks/leaps-vertical-fix.md S2，業界稱 T+0 曲線）。
  #
  # 1. 以報價日兩腳 mid 反推 IV（BS 歐式、連續股息率 q = 年股息 ÷ S₀）。
  # 2. 平倉日 t、股價 S、IV 調整 ΔIV（百分點，兩腳同步）→ 兩腳價值 V；τ = (到期日 − t) ÷ 365，
  #    τ ≤ 0 不呼叫 BS，直接取內在價值 max(S − K, 0)。
  # 3. 平倉損益 = (V(LC) − V(SC) − mid 淨成本) × 100 × 口數 − 來回費用；
  #    保守版以半價差 h 吃進兩腳：(V(LC) − h_LC) − (V(SC) + h_SC)，下限 0，對保守淨成本。
  class CloseOut
    DAYS_PER_YEAR = 365
    IV_FLOOR = BigDecimal("0.005")
    STALE_AFTER = 15.minutes
    ASSIGNMENT_WINDOW_DAYS = 90 # 使用者裁示：沒有除息日資料，剩一季以上且有配息就視為會經過除息
    IV_FAILURE = "無法反推 IV，平倉損益不可用"

    attr_reader :error, :ivs

    def initialize(long:, short:, spot:, quote_date:, expiry:, contracts: 1,
                   fee_per_leg: Config.fee_per_contract_leg, rate: Config.risk_free_rate, dividend_annual: nil,
                   spot_quoted_at: nil, option_quoted_at: nil, iv_bounds: Config.iv_bounds)
      @legs = { long: long, short: short }
      @spot = spot
      @quote_date = quote_date
      @expiry = expiry
      @contracts = contracts
      @fee_per_leg = fee_per_leg
      @rate = rate
      @dividend_annual = dividend_annual
      @q = dividend_annual && spot.positive? ? dividend_annual / spot : BigDecimal("0")
      @quoted_at = [ spot_quoted_at, option_quoted_at ]
      @ivs = solve_ivs(iv_bounds)
      @error = IV_FAILURE unless @ivs
    end

    def call(price:, date:, iv_shift: BigDecimal("0"))
      return { error: @error } if @error
      return { error: "平倉日須介於報價日 #{@quote_date} 與到期日 #{@expiry} 之間" } unless date.between?(@quote_date, @expiry)

      long_v = leg_value(:long, price, date, iv_shift)
      short_v = leg_value(:short, price, date, iv_shift)
      value = long_v - short_v
      { value: value, pnl: pnl(value, Metrics.leg_price(@legs[:long]) - Metrics.leg_price(@legs[:short])),
        **conservative(long_v, short_v), flags: flags(price, date), ivs: @ivs }
    end

    # 單腳在股價 S、日期 t 的理論價值（BigDecimal）。
    def leg_value(leg, price, date, iv_shift = BigDecimal("0"))
      strike = @legs[leg][:strike]
      tau = tau_from(date)
      return [ price - strike, BigDecimal("0") ].max unless tau.positive?

      sigma = [ @ivs[leg] + iv_shift / 100, IV_FLOOR ].max
      BigDecimal(BlackScholes.call_price(spot: price, strike: strike, tau: tau, rate: @rate, q: @q, sigma: sigma).to_s)
    end

    # 與股價、平倉日無關的旗標：區塊一載入就要顯示（S3 第 10 點）。
    def quote_flags
      spot_at, option_at = @quoted_at
      { stale_quote: !!(spot_at && option_at && (spot_at - option_at).abs > STALE_AFTER),
        dividend_unknown: @dividend_annual.nil? }
    end

    private

    # T = 日曆天數 ÷ 365（通則 7）。
    def tau_from(date) = BigDecimal((@expiry - date).to_i) / DAYS_PER_YEAR

    def solve_ivs(bounds)
      tau = tau_from(@quote_date)
      return nil unless tau.positive?

      ivs = @legs.transform_values { |leg| solve_iv(leg, tau, bounds) }
      ivs.values.all? ? ivs : nil
    end

    # 超出無套利範圍（低於 S₀·e^(−qT) − K·e^(−rT) 或高於 S₀）直接判失敗；S0 盤點沒有 Barchart IV 可退回。
    def solve_iv(leg, tau, bounds)
      mid = Metrics.leg_price(leg)
      return nil unless mid

      params = { spot: @spot, strike: leg[:strike], tau: tau, rate: @rate, q: @q }
      floor = @spot.to_f * Math.exp(-@q.to_f * tau.to_f) - leg[:strike].to_f * Math.exp(-@rate.to_f * tau.to_f)
      return nil if mid.to_f < floor || mid > @spot

      sigma = BlackScholes.implied_vol(price: mid, bounds: bounds, **params)
      sigma && BigDecimal(sigma.to_s)
    end

    def conservative(long_v, short_v)
      nat_cost = Metrics.conservative_cost(@legs[:long], @legs[:short])
      return { value_conservative: nil, pnl_conservative: nil } unless nat_cost

      value = [ (long_v - half_spread(:long)) - (short_v + half_spread(:short)), BigDecimal("0") ].max
      { value_conservative: value, pnl_conservative: pnl(value, nat_cost) }
    end

    def half_spread(leg) = (@legs[leg][:ask] - @legs[leg][:bid]) / 2

    def pnl(value, net_cost)
      round_trip_fee = @fee_per_leg * 2 * @contracts * 2
      (value - net_cost) * CONTRACT_MULTIPLIER * @contracts - round_trip_fee
    end

    def flags(price, date)
      quote_flags.merge(
        early_assignment_risk: !!(@dividend_annual&.positive? && price > @legs[:short][:strike] &&
                                  (@expiry - date).to_i >= ASSIGNMENT_WINDOW_DAYS)
      )
    end
  end
end
