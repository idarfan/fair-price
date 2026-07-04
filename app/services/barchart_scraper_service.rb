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
#
#   # LEAPS chain fetch (all expirations, Options Prices + V&G merged):
#   result = BarchartScraperService.new("NOK").fetch_leaps
#   result[:status]  # => "success" | "cached" | "partial_error" | "barchart_session_expired" | "error"
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

  # User-triggered LEAPS chain fetch: Options Prices + V&G for all expirations.
  # Returns :cached if the symbol was already scraped within the last 5 minutes.
  def fetch_leaps(user_strike: nil)
    result = { symbol: @symbol, status: nil, errors: [] }

    unless cdp_available?
      result[:status] = "error"
      result[:errors] << "Chrome CDP not reachable at #{CDP_URL}"
      log_fetch("leaps", "error", "CDP unavailable")
      return result
    end

    if LeapsOptionChainSnapshot.for_symbol(@symbol).fresh.exists?
      result[:status] = "cached"
      log_fetch("leaps", "cached", nil)
      return result
    end

    fetch_result = run_scraper("leaps", extra_args: user_strike ? [user_strike.to_s] : [])

    case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("leaps", "barchart_session_expired", nil)
      result[:status] = "barchart_session_expired"
    when "no_candidates"
      log_fetch("leaps", "no_candidates", "user_strike=#{user_strike}")
      result[:status] = "no_candidates"
    when "success"
      persist_chain_snapshot(fetch_result[:data])
      persist_leaps(fetch_result[:data])
      log_fetch("leaps", "success", "rows=#{fetch_result[:data]["rows"]&.length}")
      result[:status] = "success"
    when "partial"
      persist_chain_snapshot(fetch_result[:data])
      persist_leaps(fetch_result[:data])
      data          = fetch_result[:data]
      expired_at    = data["expired_at_strike"] || data["expired_at_expiration"]
      expired_layer = data["expired_layer"]
      reason        = data["reason"] || "unknown"
      skipped       = Array(data["skipped_strikes"])
      layer_label   = expired_layer == "volatility_greeks" ? "Volatility & Greeks" : "Options Prices"
      location_label = data["expired_at_strike"] ? "Strike #{expired_at}" : expired_at.to_s
      log_fetch("leaps", "partial_error",
                "expired_at=#{expired_at} layer=#{expired_layer} reason=#{reason} skipped=#{skipped.map { |s| "#{s["strike"]}/#{s["layer"]}" }.join(",")}")
      skipped.each do |s|
        Rails.logger.warn("[leaps] skipped strike=#{s["strike"]} layer=#{s["layer"]} (empty after stability check)")
      end
      result[:status] = "partial_error"
      result[:errors] << case reason
                         when "session_expired"
                           "Session 已過期（抓取 #{location_label} 的 #{layer_label} 時格線出現登入提示），請重新登入 Barchart 後重試"
                         when "page_load_timeout"
                           "抓取 #{location_label} 的 #{layer_label} 時頁面 30 秒內未完成載入（非 Session 問題），請稍後重試"
                         else
                           "抓取 #{location_label} 的 #{layer_label} 時格線無回應，請確認 Barchart 仍在登入狀態後重試"
                         end
    when "invalid_strike"
      data = fetch_result[:data]
      persist_chain_snapshot(data)
      log_fetch("leaps", "invalid_strike", "user_strike=#{user_strike} symbol=#{@symbol}")
      result[:status] = "invalid_strike"
      result[:errors] << data["message"].to_s
    else
      log_fetch("leaps", "error", fetch_result[:error])
      result[:status] = "error"
      result[:errors] << fetch_result[:error].to_s
    end

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
      case data["status"]
      when "barchart_session_expired"
        { status: "barchart_session_expired" }
      when "no_candidates"
        { status: "no_candidates" }
      when "partial"
        { status: "partial", data: data }
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
        symbol:               @symbol,
        snapshot_date:        @today,
        fetched_at:           now,
        max_pain_by_expiry:   data["max_pain_by_expiry"],
        available_expirations: data["available_expirations"] || [],
        created_at:           now,
        updated_at:           now
      },
      unique_by: [:symbol, :snapshot_date],
      update_only: [:fetched_at, :max_pain_by_expiry, :available_expirations]
    )
  end

  def persist_leaps(data)
    rows = data["rows"]
    return if rows.blank?

    now = Time.current
    records = rows.map do |r|
      {
        symbol:           @symbol,
        expiration_date:  r["expiration_date"],
        dte:              r["dte"],
        strike:           r["strike"],
        option_type:      r["option_type"],
        bid:              r["bid"],
        ask:              r["ask"],
        last_price:       r["last_price"],
        underlying_price: r["underlying_price"],
        volume:           r["volume"],
        open_interest:    r["open_interest"],
        delta:            r["delta"],
        iv:               r["iv"],
        itm_probability:  r["itm_probability"],
        vol_oi_ratio:     r["vol_oi_ratio"],
        vega:             r["vega"],
        scraped_at:       now,
        created_at:       now,
        updated_at:       now
      }
    end

    # 防護性驗證：insert_all 不觸發 model validation，在此手動檢查必要欄位，
    # 讓呼叫端（ScrapeLeapsJob rescue block）可以把人話訊息寫進 leaps_last_errors。
    incomplete = records.count { |r| r[:expiration_date].blank? || r[:strike].blank? || r[:option_type].blank? }
    if incomplete > 0
      raise "LEAPS 資料不完整（#{incomplete}/#{records.size} 筆缺少到期日、履約價或選擇權類型），請重新查詢"
    end

    # Wrapped in a transaction: if insert_all fails, delete_all is rolled back
    # so callers never see a state where the old data is gone but nothing replaced it.
    ActiveRecord::Base.transaction do
      LeapsOptionChainSnapshot.where(symbol: @symbol).delete_all
      LeapsOptionChainSnapshot.insert_all(records)
    end
  end

  def persist_chain_snapshot(data)
    snap = data["chain_snapshot"]
    return unless snap.is_a?(Hash)

    strikes  = Array(snap["strikes"]).map(&:to_f)
    spot     = snap["spot_price"]&.to_f
    return if strikes.empty?

    StrikeChainSnapshot.upsert(
      { symbol: @symbol, strikes: strikes, spot_price: spot, scraped_at: Time.current },
      unique_by: :symbol,
      update_only: %i[strikes spot_price scraped_at]
    )
  rescue => e
    Rails.logger.error("[leaps] persist_chain_snapshot failed: #{e.message}")
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
  rescue => e
    Rails.logger.warn("[BarchartScraperService] log_fetch failed (type=#{type} status=#{status}): #{e.message}")
  end
end
