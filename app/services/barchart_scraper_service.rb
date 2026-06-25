require "open3"

# Scrapes Technical Analysis, Fundamentals, Options Flow, and Max Pain from Barchart
# using an existing Chrome CDP session (user must be logged in manually).
#
# Usage:
#   result = BarchartScraperService.new("MU").call
#   result[:status]  # => "success" | "barchart_session_expired" | "error"
#
#   # UI-triggered filter re-fetch (does NOT update the contract snapshot):
#   result = BarchartScraperService.new("RKLB").fetch_max_pain(
#     expiration: "2026-08-21 (m)", strikes: "near_money", volume_oi: "volume"
#   )
class BarchartScraperService
  CDP_URL    = "http://127.0.0.1:9222"
  SCRIPT_DIR = Rails.root.join("lib", "barchart_scrapers")

  def initialize(symbol)
    @symbol = symbol.upcase
    @today  = Date.today
  end

  # Full daily fetch: all four scraper types, all charts, updates contract snapshot.
  def call
    result = { symbol: @symbol, status: nil, errors: [] }

    unless cdp_available?
      result[:status] = "error"
      result[:errors] << "Chrome CDP not reachable at #{CDP_URL}"
      log_fetch("technical", "error", "CDP unavailable")
      return result
    end

    %w[technical fundamental options_flow max_pain].each do |type|
      fetch_result = run_scraper(type)
      if fetch_result[:status] == "barchart_session_expired"
        result[:status] = "barchart_session_expired"
        log_fetch(type, "barchart_session_expired", nil)
        return result
      elsif fetch_result[:status] == "success"
        if type == "max_pain"
          persist_max_pain(fetch_result[:data])
        else
          persist(type, fetch_result[:data])
        end
        if type == "options_flow" && (csv_err = fetch_result[:data]["csv_error"])
          result[:errors] << "options_flow csv: #{csv_err}"
          log_fetch(type, "partial_error", "csv_error=#{csv_err}")
        else
          log_fetch(type, "success", nil)
        end
      else
        result[:errors] << "#{type}: #{fetch_result[:error]}"
        log_fetch(type, "error", fetch_result[:error])
      end

      sleep(rand(3.0..6.0)) unless type == "options_flow"
    end

    result[:status] = result[:errors].empty? ? "success" : "partial_error"
    result
  end

  # UI-triggered max pain fetch for a specific filter combination.
  # Chart 4 (Max Pain by Contract) is filter-independent — NOT re-upserted here.
  def fetch_max_pain(expiration: nil, strikes: "show_all", volume_oi: "open_interest")
    return { status: "error", error: "CDP unavailable" } unless cdp_available?

    extra_args = build_max_pain_args(expiration, strikes, volume_oi)
    fetch_result = run_scraper("max_pain", extra_args: extra_args)

    case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("max_pain", "barchart_session_expired", nil)
      { status: "barchart_session_expired" }
    when "success"
      persist_max_pain(fetch_result[:data], update_contract_snapshot: false)
      log_fetch("max_pain", "success", "filter=#{expiration}|#{strikes}|#{volume_oi}")
      { status: "success", data: fetch_result[:data] }
    else
      log_fetch("max_pain", "error", fetch_result[:error])
      { status: "error", error: fetch_result[:error] }
    end
  end

  private

  def cdp_available?
    uri = URI.parse("#{CDP_URL}/json/version")
    Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
  rescue
    false
  end

  # Convert UI filter values to CLI positional args for the Python scraper.
  # Strips Angular "string:" prefix from expiration if present.
  def build_max_pain_args(expiration, strikes, volume_oi)
    return [] unless expiration.present?

    # "string:2026-08-21 (m)" or "2026-08-21 (m)" -> "2026-08-21-m"
    cli_expiry = expiration.to_s
                           .delete_prefix("string:")
                           .strip
                           .gsub(" (", "-")
                           .delete_suffix(")")
    [cli_expiry, strikes.to_s, volume_oi.to_s]
  end

  def run_scraper(type, extra_args: [])
    script = SCRIPT_DIR.join("#{type}_scraper.py")
    stdout, stderr, status = Open3.capture3(
      "python3", script.to_s, @symbol, *extra_args,
      chdir: Rails.root.to_s
    )

    if status.success?
      data = JSON.parse(stdout)
      if data["status"] == "barchart_session_expired"
        { status: "barchart_session_expired" }
      else
        { status: "success", data: data }
      end
    else
      { status: "error", error: stderr.strip.first(500) }
    end
  rescue JSON::ParserError => e
    { status: "error", error: "JSON parse error: #{e.message}" }
  end

  def persist(type, data)
    model = {
      "technical"    => TechnicalAnalysis,
      "fundamental"  => Fundamental,
      "options_flow" => OptionsFlow
    }[type]

    permitted = data.select { |k, _| model.column_names.include?(k.to_s) }
                    .transform_keys(&:to_sym)
    permitted[:fetched_at] = Time.current

    record = model.find_or_initialize_by(symbol: @symbol, snapshot_date: @today)
    record.assign_attributes(permitted)
    record.save!

    persist_trades(data["trades"]) if type == "options_flow" && data["trades"].is_a?(Array)
  end

  def persist_max_pain(data, update_contract_snapshot: true)
    now = Time.current

    # Table 1: filter-dependent (charts 1-3), unique on 5-column filter combo
    MaxPainSnapshot.upsert(
      {
        symbol:             @symbol,
        snapshot_date:      @today,
        expiration:         data["expiration"],
        strikes_filter:     data["strikes_filter"],
        volume_oi_filter:   data["volume_oi_filter"],
        fetched_at:         now,
        dte:                data["dte"],
        last_price:         data["last_price"],
        max_pain_strike:    data["max_pain_strike"],
        strikes:            data["strikes"],
        call_pain:          data["call_pain"],
        put_pain:           data["put_pain"],
        call_oi:            data["call_oi"],
        put_oi:             data["put_oi"],
        iv_combined:        data["iv_combined"],
        created_at:         now,
        updated_at:         now
      },
      unique_by: [:symbol, :snapshot_date, :expiration, :strikes_filter, :volume_oi_filter],
      update_only: [:fetched_at, :dte, :last_price, :max_pain_strike,
                    :strikes, :call_pain, :put_pain, :call_oi, :put_oi, :iv_combined]
    )

    return unless update_contract_snapshot

    # Table 2: filter-independent (chart 4), unique on symbol+date
    MaxPainContractSnapshot.upsert(
      {
        symbol:             @symbol,
        snapshot_date:      @today,
        fetched_at:         now,
        max_pain_by_expiry: data["max_pain_by_expiry"],
        created_at:         now,
        updated_at:         now
      },
      unique_by: [:symbol, :snapshot_date],
      update_only: [:fetched_at, :max_pain_by_expiry]
    )
  end

  def persist_trades(trades)
    return if trades.empty?

    now = Time.current
    classified = trades.map { |t| classify_trade(t, now) }

    OptionsFlowTrade.where(symbol: @symbol, snapshot_date: @today).delete_all
    OptionsFlowTrade.insert_all(classified)
  end

  def classify_trade(trade, fetched_at)
    c = OptionsFlowClassifierService.classify(trade)

    {
      symbol:               @symbol,
      snapshot_date:        @today,
      fetched_at:           fetched_at,
      option_type:          c["option_type"],
      strike:               c["strike"],
      expires_at:           c["expires_at"],
      dte:                  c["dte"],
      trade_price:          c["trade_price"],
      size:                 c["size"],
      side:                 c["side"],
      premium:              c["premium"],
      volume:               c["volume"],
      open_interest:        c["open_interest"],
      iv:                   c["iv"],
      delta:                c["delta"],
      trade_condition:      c["trade_condition"].presence,
      open_close:           c["open_close"],
      trade_time:           c["trade_time"],
      is_cancelled:         c["is_cancelled"],
      is_multi_leg:         c["is_multi_leg"],
      is_stock_combo:       c["is_stock_combo"],
      urgency_high:         c["urgency_high"],
      likely_institutional: c["likely_institutional"],
      low_liquidity_period: c["low_liquidity_period"],
      timing_anomaly:       c["timing_anomaly"],
      large_premium:        c["large_premium"],
      created_at:           fetched_at,
      updated_at:           fetched_at
    }
  end

  def log_fetch(type, status, detail)
    FetchLog.create!(
      symbol:       @symbol,
      fetch_type:   type,
      status:       status,
      error_detail: detail,
      fetched_at:   Time.current
    )
  end
end
