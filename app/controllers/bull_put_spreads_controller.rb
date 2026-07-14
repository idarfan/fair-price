# frozen_string_literal: true

# BPUS §3.1：代號驗證固定用 \A[A-Z.]{1,6}\z（規格明講），跟其他工具用
# gsub(/[^A-Z0-9.\-]/, "") 消毒後照單全收不同——這裡不符合格式直接擋，不猜測。
class BullPutSpreadsController < ApplicationController
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
      cached = Rails.cache.read("bpus_expirations_#{@symbol}")
      if cached
        @scrape_status = :cached
        @expirations   = build_expiration_options(cached[:expirations])
        @underlying_price = cached[:underlying_price]
      elsif params[:job_status].present?
        @scrape_status = job_status_symbol(params[:job_status])
      else
        @scrape_status = :ready_to_fetch
      end
    end

    @expiration = params[:expiration].presence
    if @symbol.present? && @expiration.present?
      chain_cached = Rails.cache.read("bpus_put_chain_#{@symbol}_#{@expiration}")
      if chain_cached
        @chain_status = :cached
        @put_chain    = chain_cached[:rows]
      elsif params[:chain_job_status].present?
        @chain_status = job_status_symbol(params[:chain_job_status])
      else
        @chain_status = :ready_to_fetch
      end
    end

    render BullPutSpreads::PageComponent.new(
      symbol:            @symbol,
      symbol_error:      @symbol_error,
      scrape_status:     @scrape_status,
      expirations:       @expirations,
      underlying_price:  @underlying_price,
      expiration:        @expiration,
      chain_status:      @chain_status,
      put_chain:         @put_chain
    )
  end

  def fetch_expirations
    symbol = params[:symbol].to_s.upcase.strip
    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?
    unless symbol.match?(SYMBOL_PATTERN)
      return render json: { error: "invalid symbol format" }, status: :unprocessable_entity
    end

    if Rails.cache.exist?("bpus_expirations_#{symbol}")
      return render json: { status: "ready", symbol: symbol }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("bpus_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    BpusFetchExpirationsJob.perform_later(symbol, job_id)

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

    if Rails.cache.exist?("bpus_put_chain_#{symbol}_#{expiration}")
      return render json: { status: "ready", symbol: symbol, expiration: expiration }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("bpus_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    BpusFetchChainJob.perform_later(symbol, expiration, job_id)

    render json: { job_id: job_id, symbol: symbol, expiration: expiration }
  end

  def status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", error: "missing job_id" }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read("bpus_job_#{job_id}")
    render json: cached || { status: "not_found" }
  end

  # 純數學，不碰 CDP，同步執行——BullPutSpreadCalculatorService 是計算的唯一
  # 權威來源，前端不自己重算一份公式（避免 JS/Ruby 兩份公式各自維護、漂移）。
  def calculate
    short_strike = params[:short_strike].to_s
    short_bid    = params[:short_bid].to_s
    long_strike  = params[:long_strike].to_s
    long_ask     = params[:long_ask].to_s

    numeric = /\A\d+(\.\d+)?\z/
    unless [ short_strike, short_bid, long_strike, long_ask ].all? { |v| v.match?(numeric) }
      return render json: { error: "short_strike, short_bid, long_strike, long_ask 必須是正數" },
                    status: :unprocessable_entity
    end

    result = BullPutSpreadCalculatorService.new(
      short_strike: short_strike.to_f,
      short_bid:    short_bid.to_f,
      long_strike:  long_strike.to_f,
      long_ask:     long_ask.to_f
    ).call

    render json: {
      short_strike: result.short_strike,
      long_strike:  result.long_strike,
      net_credit:   result.net_credit,
      width:        result.width,
      max_profit:   result.max_profit,
      max_loss:     result.max_loss,
      margin:       result.margin,
      breakeven:    result.breakeven,
      roc:          result.roc,
      risk_reward:  result.risk_reward,
      warning:      result.warning
    }
  end

  # bpus-fix.md 項目6：背景波動率資料。前端頁面載入後打這支輪詢；第一次呼叫
  # 若快取不存在就背景排 job 並回 pending，不阻塞、不等待 job 完成再回應。
  # pending guard 用短 TTL 避免使用者輪詢期間重複排多個 job。
  def volatility
    symbol     = params[:symbol].to_s.upcase.strip
    expiration = params[:expiration].to_s.strip
    return render json: { status: "error" }, status: :unprocessable_entity if symbol.blank? || expiration.blank?

    cached = Rails.cache.read("bpus_volatility_#{symbol}_#{expiration}")
    return render json: cached if cached

    pending_key = "bpus_volatility_pending_#{symbol}_#{expiration}"
    unless Rails.cache.exist?(pending_key)
      Rails.cache.write(pending_key, true, expires_in: 30.seconds)
      BpusVolatilityJob.perform_later(symbol, expiration)
    end

    render json: { status: "pending" }
  end

  private

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
