# frozen_string_literal: true

# Fetches options chain from Yahoo Finance (public API, no auth required).
# Computes Max Pain and Vol Skew chart data for dashboard rendering.
class OptionsChainService
  BASE_URL = "https://query1.finance.yahoo.com/v7/finance/options"
  HEADERS  = {
    "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Accept"     => "application/json,*/*",
    "Referer"    => "https://finance.yahoo.com"
  }.freeze

  def initialize(symbol)
    @symbol = symbol.upcase
  end

  def call
    chain = fetch_chain
    return nil unless chain

    spot     = chain.dig("quote", "regularMarketPrice").to_f
    opts     = chain.dig("options", 0) || {}
    calls    = opts["calls"]  || []
    put_opts = opts["puts"]   || []
    expiry   = opts["expirationDate"]&.then { |t| Time.at(t).utc.strftime("%Y-%m-%d") }

    {
      expiry:        expiry,
      current_price: spot,
      max_pain:      compute_max_pain(calls, put_opts, spot),
      vol_skew:      compute_vol_skew(calls, put_opts, spot)
    }
  rescue StandardError => e
    Rails.logger.warn("[OptionsChainService] #{@symbol}: #{e.message}")
    nil
  end

  private

  def fetch_chain
    resp = HTTParty.get(
      "#{BASE_URL}/#{@symbol}",
      headers: HEADERS,
      timeout: 12
    )
    return nil unless resp.success?
    resp.parsed_response.dig("optionChain", "result", 0)
  end

  def compute_max_pain(calls, put_opts, spot)
    call_oi = calls.each_with_object({}) { |c, h| h[c["strike"].to_f] = c["openInterest"].to_i }
    put_oi  = put_opts.each_with_object({}) { |p, h| h[p["strike"].to_f] = p["openInterest"].to_i }

    all_strikes = (call_oi.keys + put_oi.keys).uniq.sort
    return nil if all_strikes.empty?

    # Limit to ±25% of spot to keep chart readable
    lo, hi = spot * 0.75, spot * 1.25
    strikes = all_strikes.select { |s| s.between?(lo, hi) }
    strikes = all_strikes if strikes.size < 5

    pain_data = strikes.map do |k|
      cp = all_strikes.sum { |s| s < k ? (k - s) * (call_oi[s] || 0) * 100 : 0 }
      pp = all_strikes.sum { |s| s > k ? (s - k) * (put_oi[s]  || 0) * 100 : 0 }
      { strike: k, call_pain: cp, put_pain: pp, total: cp + pp }
    end

    mp_strike = pain_data.min_by { |d| d[:total] }&.dig(:strike)
    { strike: mp_strike, chart_data: pain_data }
  end

  def compute_vol_skew(calls, put_opts, spot)
    lo, hi = spot * 0.75, spot * 1.25

    call_iv = calls.each_with_object({}) do |c, h|
      s = c["strike"].to_f
      iv = c["impliedVolatility"].to_f * 100
      h[s] = iv.round(2) if s.between?(lo, hi) && iv > 0.1
    end
    put_iv = put_opts.each_with_object({}) do |p, h|
      s = p["strike"].to_f
      iv = p["impliedVolatility"].to_f * 100
      h[s] = iv.round(2) if s.between?(lo, hi) && iv > 0.1
    end

    strikes = (call_iv.keys + put_iv.keys).uniq.sort
    chart_data = strikes.map { |s| { strike: s, call_iv: call_iv[s], put_iv: put_iv[s] } }
    { current_price: spot, chart_data: chart_data }
  end
end
