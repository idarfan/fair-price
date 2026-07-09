# frozen_string_literal: true

class LeapsRecommendationsController < ApplicationController
  def index
    @symbol        = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    @candidates    = []
    @flow_panel    = nil
    @scrape_status = nil
    @scrape_errors = []

    @user_strike = params[:user_strike].presence

    if @symbol.present?
      if fresh_data_exists?(@symbol, user_strike: @user_strike&.to_f)
        @candidates    = LeapsRankingService.new(@symbol).call
        @recommendation = LeapsRecommendationService.new(@candidates).call
        @flow_panel     = LeapsOptionsFlowPanelService.new(@symbol, @candidates).call

        @scrape_status = :cached

        case params[:job_status]
        when "session_expired"
          @scrape_status = :session_expired
        when "cdp_offline"
          @scrape_status = :cdp_offline
        when "partial_error"
          @scrape_status = :partial_error
          @scrape_errors = cached_errors(@symbol)
        when "error"
          @scrape_status = :error
          @scrape_errors = cached_errors(@symbol)
        when "no_candidates"
          @scrape_status = :no_candidates
        when "invalid_strike"
          @scrape_status = :invalid_strike
          @scrape_errors = cached_errors(@symbol)
        end

        # When analyze returned "ready" (no job_status forwarded) but candidates
        # are empty, determine the correct status from the last cached error state.
        if @candidates.empty? && @scrape_status == :cached
          last_errors = cached_errors(@symbol)
          if last_errors.any?
            @scrape_status = :partial_error
            @scrape_errors = last_errors
          else
            @scrape_status = :no_candidates
          end
        end
      elsif params[:job_status].present?
        case params[:job_status]
        when "session_expired"
          @scrape_status = :session_expired
        when "cdp_offline"
          @scrape_status = :cdp_offline
        when "no_candidates"
          @scrape_status = :no_candidates
        when "partial_error"
          @scrape_status = :partial_error
          @scrape_errors = cached_errors(@symbol)
        else
          @scrape_status = :error
          @scrape_errors = cached_errors(@symbol)
        end
      else
        @scrape_status = :ready_to_fetch
      end
    end

    # 推薦分析圖卡的 {latest_earnings}：唯讀既有 fundamentals（Barchart overview 抓取），
    # 不新增 service、不打外部 API；無資料時 component 端降級顯示。
    next_earnings = @symbol.present? ?
      Fundamental.where(symbol: @symbol).order(:updated_at).last&.next_earnings_date : nil

    render LeapsRecommendations::PageComponent.new(
      symbol:         @symbol,
      candidates:     @candidates,
      recommendation: @recommendation,
      flow_panel:     @flow_panel,
      scrape_status:  @scrape_status,
      scrape_errors:  @scrape_errors,
      user_strike:    @user_strike,
      next_earnings:  next_earnings
    )
  end

  def analyze
    symbol = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?

    user_strike = nil
    if params[:user_strike].present?
      raw = params[:user_strike].to_s.strip
      if raw.match?(/\A\d+(\.\d{1,2})?\z/) && raw.to_f > 0
        user_strike = raw.to_f
      else
        return render json: { error: "user_strike 必須是正數（最多兩位小數）" }, status: :unprocessable_entity
      end
    end

    # Controller-layer snapshot validation (fast path — no scrape needed)
    if user_strike
      snap = StrikeChainSnapshot.find_by(symbol: symbol)
      if snap && !snap.valid_strike?(user_strike)
        return render json: {
          status:  "invalid_strike",
          message: snap.invalid_message(symbol, user_strike)
        }
      end
    end

    if fresh_data_exists?(symbol, user_strike: user_strike)
      return render json: { status: "ready", symbol: symbol, user_strike: user_strike }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("leaps_job_#{job_id}", { status: "pending" }, expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW)
    ScrapeLeapsJob.perform_later(symbol, job_id, user_strike: user_strike)

    render json: { job_id: job_id, symbol: symbol, user_strike: user_strike }
  end

  def status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", error: "missing job_id" }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read("leaps_job_#{job_id}")
    render json: cached || { status: "not_found" }
  end

  private

  # user_strike 有值時，快取除了要「時間新鮮」還要「涵蓋這個中心履約價」——
  # 否則使用者換一個履約價重新查詢，會誤用上一次查詢（不同中心點）留下的舊候選，
  # 畫面顯示的推薦履約價跟輸入值完全無關（2026-07-09 NOK 履約價 7 查出 2 候選的成因）。
  # 緩衝寬度呼應 leaps_scraper.py Stage 1 的「中心履約價 ±1 檔」設計，用比例逼近避免與
  # 爬蟲端的實際檔位邏輯脫鉤；低價股（如 -）另設最低  緩衝避免視窗過窄。
  def fresh_data_exists?(symbol, user_strike: nil)
    scope = LeapsOptionChainSnapshot.for_symbol(symbol).fresh
    return false unless scope.exists?
    return true if user_strike.blank?

    buffer = [ user_strike.to_f * 0.25, 1.0 ].max
    scope.where(strike: (user_strike.to_f - buffer)..(user_strike.to_f + buffer)).exists?
  end

  def cached_errors(symbol)
    Array(Rails.cache.read("leaps_last_errors_#{symbol}"))
  end

  def cdp_online?
    require "net/http"
    uri  = URI("http://localhost:9222/json/version")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    http.get(uri.path).is_a?(Net::HTTPSuccess)
  rescue
    false
  end
end
