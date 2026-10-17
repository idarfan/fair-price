# frozen_string_literal: true

module HallOfFame
  # Black-Scholes 歐式期權理論價與歷史波動率（規格 P3b bs_model）。純計算，無 I/O。
  module BlackScholes
    TRADING_DAYS_PER_YEAR = 252

    module_function

    # s：標的價、k：履約價、t：年、r：無風險利率、sigma：年化波動率、right："call"／"put"
    def price(s:, k:, t:, r:, sigma:, right:)
      raise ArgumentError, "t、sigma 必須 > 0" unless t.positive? && sigma.positive?

      d1 = (Math.log(s / k) + ((r + (sigma**2 / 2)) * t)) / (sigma * Math.sqrt(t))
      d2 = d1 - (sigma * Math.sqrt(t))
      discount = k * Math.exp(-r * t)
      right == "call" ? (s * cdf(d1)) - (discount * cdf(d2)) : (discount * cdf(-d2)) - (s * cdf(-d1))
    end

    # closes：依時間正序的收盤價；回傳年化歷史波動率（對數報酬樣本標準差 × √252）。
    def historical_volatility(closes)
      returns = closes.each_cons(2).map { |a, b| Math.log(b / a) }
      raise ArgumentError, "至少需要 2 個報酬" if returns.size < 2

      mean     = returns.sum / returns.size
      variance = returns.sum { |x| (x - mean)**2 } / (returns.size - 1)
      Math.sqrt(variance) * Math.sqrt(TRADING_DAYS_PER_YEAR)
    end

    def cdf(x) = 0.5 * (1 + Math.erf(x / Math.sqrt(2)))
  end
end
