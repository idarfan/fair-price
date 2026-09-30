# frozen_string_literal: true

class LeapsVerticalSpreadService
  # 歐式買權 Black-Scholes（含連續股息率 q）與二分法反推 IV（tasks/leaps-vertical-fix.md S2）。
  # 超越函數用 Float 計算；呼叫端負責在 τ ≤ 0 時改用內在價值，這裡只接受 τ > 0。
  module BlackScholes
    IV_TOLERANCE = 1e-6
    MAX_ITERATIONS = 200

    module_function

    def call_price(spot:, strike:, tau:, rate:, q:, sigma:)
      spot, strike, tau, rate, q, sigma = [ spot, strike, tau, rate, q, sigma ].map(&:to_f)
      sigma_sqrt_t = sigma * Math.sqrt(tau)
      d1 = (Math.log(spot / strike) + (rate - q + sigma**2 / 2) * tau) / sigma_sqrt_t
      d2 = d1 - sigma_sqrt_t
      spot * Math.exp(-q * tau) * cdf(d1) - strike * Math.exp(-rate * tau) * cdf(d2)
    end

    # 反推失敗（價格落在 bounds 兩端的理論價之外）回 nil，不回 NaN。
    def implied_vol(price:, bounds:, **params)
      target = price.to_f
      lo = bounds.begin.to_f
      hi = bounds.end.to_f
      return nil unless call_price(**params, sigma: lo) <= target && target <= call_price(**params, sigma: hi)

      MAX_ITERATIONS.times do
        mid = (lo + hi) / 2
        diff = call_price(**params, sigma: mid) - target
        return mid if diff.abs < IV_TOLERANCE

        diff.positive? ? hi = mid : lo = mid
      end
      (lo + hi) / 2
    end

    def cdf(x) = 0.5 * Math.erfc(-x / Math.sqrt(2))
  end
end
