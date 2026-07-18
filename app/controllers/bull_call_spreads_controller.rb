# frozen_string_literal: true

# bcvs.md §路由與入口：代號驗證固定用 \A[A-Z.]{1,6}\z，比照 bpus 分工
# （BullPutSpreadsController::SYMBOL_PATTERN）。
class BullCallSpreadsController < ApplicationController
  SYMBOL_PATTERN = /\A[A-Z.]{1,6}\z/

  def index
    @symbol = params[:symbol].to_s.upcase.strip
    @symbol = nil if @symbol.blank?

    @symbol_error  = nil
    @expirations   = nil
    @scrape_status = nil

    if @symbol.present? && !@symbol.match?(SYMBOL_PATTERN)
      @symbol_error = "股票代號格式錯誤，僅接受 1-6 位大寫英文字母或句點"
      @symbol = nil
    end

    if @symbol.present?
      if BcvsCacheService.fresh_expirations?(@symbol)
        cached             = BcvsCacheService.read_expirations(@symbol)
        @scrape_status     = :cached
        @expirations       = build_expiration_options(cached[:expirations])
        @underlying_price  = cached[:underlying_price]
      elsif params[:job_status].present?
        @scrape_status = job_status_symbol(params[:job_status])
      else
        @scrape_status = :ready_to_fetch
      end
    end

    @expiration = params[:expiration].presence
    if @symbol.present? && @expiration.present?
      if BcvsCacheService.fresh_chain?(@symbol, @expiration)
        chain_cached  = BcvsCacheService.read_chain(@symbol, @expiration)
        @chain_status = :cached
        @call_chain   = chain_cached[:strikes]
      elsif params[:chain_job_status].present?
        @chain_status = job_status_symbol(params[:chain_job_status])
      else
        @chain_status = :ready_to_fetch
      end
    end

    @k1 = params[:k1].presence

    render BullCallSpreads::PageComponent.new(
      symbol:            @symbol,
      symbol_error:      @symbol_error,
      scrape_status:     @scrape_status,
      expirations:       @expirations,
      underlying_price:  @underlying_price,
      expiration:        @expiration,
      chain_status:      @chain_status,
      call_chain:        @call_chain,
      k1:                @k1
    )
  end

  def fetch_expirations
    symbol = params[:symbol].to_s.upcase.strip
    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?
    unless symbol.match?(SYMBOL_PATTERN)
      return render json: { error: "invalid symbol format" }, status: :unprocessable_entity
    end

    if BcvsCacheService.fresh_expirations?(symbol)
      return render json: { status: "ready", symbol: symbol }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("bcvs_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    BcvsFetchExpirationsJob.perform_later(symbol, job_id)

    render json: { job_id: job_id, symbol: symbol }
  end

  def fetch_chain
    symbol     = params[:symbol].to_s.upcase.strip
    expiration = params[:expiration].to_s.strip

    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?
    unless symbol.match?(SYMBOL_PATTERN)
      return render json: { error: "invalid symbol format" }, status: :unprocessable_entity
    end
    return render json: { error: "expiration required" }, status: :unprocessable_entity if expiration.blank?

    if BcvsCacheService.fresh_chain?(symbol, expiration)
      return render json: { status: "ready", symbol: symbol, expiration: expiration }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("bcvs_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    BcvsFetchChainJob.perform_later(symbol, expiration, job_id)

    render json: { job_id: job_id, symbol: symbol, expiration: expiration }
  end

  def status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", error: "missing job_id" }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read("bcvs_job_#{job_id}")
    render json: cached || { status: "not_found" }
  end

  # bcvs.md §功能流程 步驟3：K2 三檔建議。純數學，不碰 CDP，同步執行——讀取
  # Postgres 快取的 chain（未新鮮則回錯誤，不在此觸發抓取，抓取一律走
  # fetch_chain 的 job 流程）。
  def recommend
    symbol     = params[:symbol].to_s.upcase.strip
    expiration = params[:expiration].to_s.strip
    k1         = params[:k1].to_s
    k1_ask     = params[:k1_ask].to_s
    k1_bid     = params[:k1_bid].to_s

    numeric = /\A\d+(\.\d+)?\z/
    unless symbol.match?(SYMBOL_PATTERN) && expiration.present? &&
           k1.match?(numeric) && k1_ask.match?(numeric)
      return render json: { error: "symbol, expiration, k1, k1_ask 必須完整且 k1/k1_ask 為正數" },
                    status: :unprocessable_entity
    end

    unless BcvsCacheService.fresh_chain?(symbol, expiration)
      return render json: { error: "chain not cached, fetch it first" }, status: :unprocessable_entity
    end

    strikes = BcvsCacheService.read_chain(symbol, expiration)[:strikes]
    tabs = BullCallSpreadRecommenderService.new(
      k1: k1.to_f, k1_ask: k1_ask.to_f, candidates: strikes,
      k1_bid: k1_bid.match?(numeric) ? k1_bid.to_f : nil
    ).call

    render json: { tabs: serialize_tabs(tabs) }
  end

  # bcvs.md §修復模式：純數學，不碰 CDP，同步執行。
  def calculate
    k1     = params[:k1].to_s
    k2     = params[:k2].to_s
    k2_bid = params[:k2_bid].to_s
    basis  = params[:basis].to_s

    numeric = /\A\d+(\.\d+)?\z/
    unless [ k1, k2, k2_bid, basis ].all? { |v| v.match?(numeric) }
      return render json: { error: "k1, k2, k2_bid, basis 必須是正數" }, status: :unprocessable_entity
    end

    k1_current_bid = params[:k1_current_bid].to_s
    k1_current_bid = k1_current_bid.match?(numeric) ? k1_current_bid.to_f : nil

    result = BullCallSpreadRepairCalculatorService.new(
      k1: k1.to_f, k2: k2.to_f, k2_bid: k2_bid.to_f, basis: basis.to_f,
      k1_current_bid: k1_current_bid
    ).call

    render json: {
      k1:                    result.k1,
      k2:                    result.k2,
      k2_bid:                result.k2_bid,
      basis:                 result.basis,
      locked_result:         result.locked_result,
      locked_result_total:   result.locked_result_total,
      breakeven_basis:       result.breakeven_basis,
      warning:               result.warning,
      below_k1_pnl:          result.below_k1_pnl,
      below_k1_pnl_total:    result.below_k1_pnl_total,
      closeout_proceeds:     result.closeout_proceeds,
      closeout_pnl:          result.closeout_pnl
    }
  end

  private

  def serialize_tabs(tabs)
    tabs.transform_values do |tab|
      r = tab[:result]
      {
        k1:            r.k1,
        k2:            tab[:k2],
        ratio:         tab[:ratio],
        target_ratio:  tab[:target_ratio],
        debit:         r.debit,
        debit_mid:     r.debit_mid,
        cost_per_contract: r.cost_per_contract,
        max_profit:    r.max_profit,
        max_loss:      r.max_loss,
        breakeven:     r.breakeven,
        risk_reward:   r.risk_reward,
        warning:       r.warning,
        s_star:            r.s_star,
        naked_cost:        r.naked_cost,
        naked_breakeven:   r.naked_breakeven,
        spread_max_value:  r.spread_max_value,
        closeout_value:    r.closeout_value,
        closeout_profit:   r.closeout_profit,
        realized_pct:      r.realized_pct
      }
    end
  end

  def job_status_symbol(job_status)
    case job_status
    when "session_expired" then :session_expired
    when "cdp_offline"     then :cdp_offline
    when "no_candidates"   then :no_candidates
    when "success"         then :cached
    else                        :error
    end
  end

  def build_expiration_options(raw_expirations)
    today = Date.today
    Array(raw_expirations).map do |value|
      date = Date.parse(value[0, 10])
      dte  = (date - today).to_i
      { value: value, date: date, dte: dte, label: "#{date} (#{dte}d)" }
    rescue ArgumentError, TypeError
      nil
    end.compact
  end

  def cdp_online?
    require "net/http"
    uri  = URI("http://localhost:9222/json/version")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    http.get(uri.path).is_a?(Net::HTTPSuccess)
  rescue
    false
  end
end
