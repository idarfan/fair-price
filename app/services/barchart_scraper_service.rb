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

    refresh_options_flow_if_stale

    if LeapsOptionChainSnapshot.fresh_for?(@symbol, user_strike: user_strike)
      result[:status] = "cached"
      log_fetch("leaps", "cached", nil)
      return result
    end

    fetch_result = run_scraper("leaps", extra_args: user_strike ? [ user_strike.to_s ] : [])

    case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("leaps", "barchart_session_expired", nil)
      result[:status] = "barchart_session_expired"
    when "no_candidates"
      log_fetch("leaps", "no_candidates", "user_strike=#{user_strike}")
      result[:status] = "no_candidates"
    when "success"
      persist_chain_snapshot(fetch_result[:data], user_strike: user_strike)
      persist_leaps(fetch_result[:data])
      log_fetch("leaps", "success", "rows=#{fetch_result[:data]["rows"]&.length}")
      result[:status] = "success"
    when "partial"
      persist_chain_snapshot(fetch_result[:data], user_strike: user_strike)
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

  # PMCC v3 §7：Short Call 三到期日快照抓取（近三個到期日 × 全履約價）。
  # 獨立於 fetch_leaps 之外——§1 鐵律「PMCC 失敗不可讓 LEAPS 查詢變 error」由
  # 呼叫端（ScrapeLeapsJob）自行 try/catch 隔離這個方法的呼叫，這裡本身不吞例外
  # （persist 層驗證失敗時仍會 raise，交給呼叫端決定要不要吞）。
  def fetch_pmcc_short_calls
    result = { symbol: @symbol, status: nil, errors: [] }

    unless cdp_available?
      result[:status] = "error"
      result[:errors] << "Chrome CDP not reachable at #{CDP_URL}"
      log_fetch("pmcc_short", "error", "CDP unavailable")
      return result
    end

    fetch_result = run_scraper("pmcc_short_call")

    case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("pmcc_short", "barchart_session_expired", nil)
      result[:status] = "barchart_session_expired"
    when "no_candidates"
      log_fetch("pmcc_short", "no_candidates", nil)
      result[:status] = "no_candidates"
    when "success"
      persist_pmcc_short_calls(fetch_result[:data])
      log_fetch("pmcc_short", "success", "rows=#{fetch_result[:data]["rows"]&.length}")
      result[:status] = "success"
    when "partial"
      persist_pmcc_short_calls(fetch_result[:data])
      data          = fetch_result[:data]
      expired_at    = data["expired_at_expiration"]
      expired_layer = data["expired_layer"]
      reason        = data["reason"] || "unknown"
      skipped       = Array(data["skipped_expirations"])
      log_fetch("pmcc_short", "partial_error",
                "expired_at=#{expired_at} layer=#{expired_layer} reason=#{reason} " \
                "skipped=#{skipped.map { |s| "#{s["expiration"]}/#{s["layer"]}" }.join(",")}")
      result[:status] = "partial_error"
      result[:errors] << "PMCC Short Call 在 #{expired_at} 時 #{expired_layer} 中斷（#{reason}），已抓部分用於組合"
    else
      log_fetch("pmcc_short", "error", fetch_result[:error])
      result[:status] = "error"
      result[:errors] << fetch_result[:error].to_s
    end

    result
  end

  # BPUS §3.1：履約日清單抓取，(symbol) 為 key，5 分鐘快取（規格明講「Rails cache
  # 即可」，不落地 DB model——跟 LEAPS/PMCC 排行不同，這是純即時互動工具，沒有
  # candidate 排序需要持久化）。
  def fetch_bpus_expirations
    unless cdp_available?
      log_fetch("bpus_expirations", "error", "CDP unavailable")
      return { status: "error", errors: [ "Chrome CDP not reachable at #{CDP_URL}" ] }
    end

    cache_key = "bpus_expirations_#{@symbol}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    fetch_result = run_scraper("bpus_expirations")

    result = case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("bpus_expirations", "barchart_session_expired", nil)
      { status: "barchart_session_expired" }
    when "no_candidates"
      log_fetch("bpus_expirations", "no_candidates", nil)
      { status: "no_candidates" }
    when "success"
      data = fetch_result[:data]
      Rails.logger.info("[bpus] expirations fetched url=#{data["debug_url"]} symbol=#{@symbol}")
      log_fetch("bpus_expirations", "success", "count=#{Array(data["expirations"]).length}")
      {
        status:            "success",
        expirations:       data["expirations"],
        underlying_price:  data["underlying_price"]
      }
    else
      log_fetch("bpus_expirations", "error", fetch_result[:error])
      { status: "error", errors: [ fetch_result[:error].to_s ] }
    end

    # 只快取成功結果——error/session_expired/no_candidates 都是暫時性狀態，
    # 快取住會讓使用者重試 5 分鐘內拿到同一個舊錯誤，不符合「重試應該重新抓」的預期。
    Rails.cache.write(cache_key, result, expires_in: 5.minutes) if result[:status] == "success"
    result
  end

  # BPUS §3.2：指定履約日的 Put 鏈抓取，(symbol, expiration) 為 key，5 分鐘快取。
  # bid/ask 皆 null/0 的過濾在此（Ruby 業務規則層），不在 Python（沿用既有分工）。
  def fetch_bpus_put_chain(expiration:)
    unless cdp_available?
      log_fetch("bpus_put_chain", "error", "CDP unavailable")
      return { status: "error", errors: [ "Chrome CDP not reachable at #{CDP_URL}" ] }
    end

    cache_key = "bpus_put_chain_#{@symbol}_#{expiration}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    fetch_result = run_scraper("bpus_put_chain", extra_args: [ expiration ])

    result = case fetch_result[:status]
    when "barchart_session_expired"
      log_fetch("bpus_put_chain", "barchart_session_expired", nil)
      { status: "barchart_session_expired" }
    when "no_candidates"
      log_fetch("bpus_put_chain", "no_candidates", "expiration=#{expiration}")
      { status: "no_candidates" }
    when "success"
      data = fetch_result[:data]
      Rails.logger.info("[bpus] put chain fetched url=#{data["debug_url"]} symbol=#{@symbol} expiration=#{expiration}")
      rows = Array(data["rows"]).select { |r| r["bid"].present? || r["ask"].present? }
      log_fetch("bpus_put_chain", "success", "rows=#{rows.length} expiration=#{expiration}")
      {
        status:            "success",
        rows:              rows,
        underlying_price:  data["underlying_price"]
      }
    else
      log_fetch("bpus_put_chain", "error", fetch_result[:error])
      { status: "error", errors: [ fetch_result[:error].to_s ] }
    end

    Rails.cache.write(cache_key, result, expires_in: 5.minutes) if result[:status] == "success"
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

  # LEAPS 查詢屬於任意 symbol，未必在 watchlist.yml 每日排程範圍內，
  # Options Flow 面板因此可能停在多天前的舊快照。查詢時順手補一次，
  # 當天已抓過就跳過；失敗僅記錄、不影響 LEAPS 查詢本身的結果。
  def refresh_options_flow_if_stale
    return if OptionsFlow.where(symbol: @symbol, snapshot_date: @today).exists?

    fetch_result = run_scraper("options_flow")
    if fetch_result[:status] == "success"
      persist("options_flow", fetch_result[:data])
      log_fetch("options_flow", "success", "triggered_by=leaps_query")
    else
      log_fetch("options_flow", "error", "triggered_by=leaps_query error=#{fetch_result[:error]}")
    end
  rescue => e
    Rails.logger.warn("[leaps] options_flow refresh failed: #{e.message}")
    log_fetch("options_flow", "error", "triggered_by=leaps_query exception=#{e.message.to_s.first(200)}")
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
    [ cli_expiry, strikes.to_s, volume_oi.to_s ]
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
      when "invalid_strike"
        { status: "invalid_strike", data: data }
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
      unique_by: [ :symbol, :snapshot_date, :expiration, :strikes_filter, :volume_oi_filter ],
      update_only: [ :fetched_at, :dte, :last_price, :max_pain_strike,
                    :strikes, :call_pain, :put_pain, :call_oi, :put_oi, :iv_combined ]
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
      unique_by: [ :symbol, :snapshot_date ],
      update_only: [ :fetched_at, :max_pain_by_expiry, :available_expirations ]
    )
  end

  def persist_leaps(data)
    rows = data["rows"]
    return if rows.blank?

    now = Time.current
    records = rows.map do |r|
      # PMCC v3 §2.1：LEAPS 無獨立 midpoint 欄位，mid 固定走 (bid+ask)/2；
      # 任一缺值 → mid=nil，derived_values 兩欄皆回 null（行為與改版前一致）。
      mid = r["bid"].nil? || r["ask"].nil? ? nil : (r["bid"].to_f + r["ask"].to_f) / 2.0
      derived = LeapsOptionChainSnapshot.derived_values(
        option_type:      r["option_type"],
        strike:           r["strike"],
        underlying_price: r["underlying_price"],
        mid:              mid
      )
      {
        symbol:           @symbol,
        expiration_date:  r["expiration_date"],
        dte:              r["dte"],
        strike:           r["strike"],
        option_type:      r["option_type"],
        bid:              r["bid"],
        ask:              r["ask"],
        intrinsic_value:  derived[:intrinsic_value],
        extrinsic_value:  derived[:extrinsic_value],
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

  def persist_pmcc_short_calls(data)
    rows = data["rows"]
    return if rows.blank?

    now = Time.current
    records = rows.map do |r|
      # PMCC v3 §2.1：mid 的唯一決定順序——Barchart midpoint 原值優先；缺值才 fallback
      # (bid+ask)/2；兩者都缺才是 nil（不以 0 代）。存入 mid_price 欄的數字，跟傳給
      # derived_values 算 extrinsic_value 用的 mid，必須是同一個數字。
      mid = if r["mid"].present?
              r["mid"].to_f
      elsif r["bid"].present? && r["ask"].present?
              (r["bid"].to_f + r["ask"].to_f) / 2.0
      end

      derived = LeapsOptionChainSnapshot.derived_values(
        option_type:      r["option_type"] || "Call",
        strike:           r["strike"],
        underlying_price: r["underlying_price"],
        mid:              mid
      )

      {
        symbol:             @symbol,
        expiration_date:    r["expiration_date"],
        dte:                r["dte"],
        strike:             r["strike"],
        option_type:        r["option_type"] || "Call",
        bid:                r["bid"],
        ask:                r["ask"],
        mid_price:          mid,
        last_price:         r["last_price"],
        moneyness:          r["moneyness"],
        underlying_price:   r["underlying_price"],
        change:             r["change"],
        percent_change:     r["percent_change"],
        volume:             r["volume"],
        open_interest:      r["open_interest"],
        oi_change:          r["oi_change"],
        vol_oi_ratio:       r["vol_oi_ratio"],
        iv:                 r["iv"],
        delta:              r["delta"],
        gamma:              r["gamma"],
        theta:              r["theta"],
        vega:               r["vega"],
        rho:                r["rho"],
        theoretical_price:  r["theoretical_price"],
        itm_probability:    r["itm_probability"],
        intrinsic_value:    derived[:intrinsic_value],
        extrinsic_value:    derived[:extrinsic_value],
        scraped_at:         now,
        created_at:         now,
        updated_at:         now
      }
    end

    # 防護性驗證：insert_all 不觸發 model validation，手動檢查必要欄位，讓呼叫端
    # （ScrapeLeapsJob 的 try/catch）可以把人話訊息寫進 log，不讓壞資料悄悄落地。
    incomplete = records.count { |r| r[:expiration_date].blank? || r[:strike].blank? || r[:strike].to_f <= 0 }
    if incomplete > 0
      raise "PMCC Short Call 資料不完整（#{incomplete}/#{records.size} 筆缺少到期日或履約價無效），請重新查詢"
    end

    ActiveRecord::Base.transaction do
      PmccShortCallSnapshot.where(symbol: @symbol).delete_all
      PmccShortCallSnapshot.insert_all(records)
    end
  end

  # user_strike: :unset（預設）＝ invalid_strike 這種只驗證、沒有實際重新爬候選
  # 的呼叫，不動 last_query_strike；success/partial 才會傳實際查詢值（含 nil＝auto
  # 模式），讓 fresh_for? 能判斷這批候選到底是為哪個中心點爬的。
  def persist_chain_snapshot(data, user_strike: :unset)
    snap = data["chain_snapshot"]
    return unless snap.is_a?(Hash)

    strikes = Array(snap["strikes"]).map(&:to_f)
    spot    = snap["spot_price"]&.to_f
    return if strikes.empty?

    values      = { symbol: @symbol, strikes: strikes, spot_price: spot, scraped_at: Time.current }
    update_cols = %i[strikes spot_price scraped_at]
    unless user_strike == :unset
      values[:last_query_strike] = user_strike
      update_cols << :last_query_strike
    end

    StrikeChainSnapshot.upsert(values, unique_by: :symbol, update_only: update_cols)
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
