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
      if fresh_data_exists?(@symbol)
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

    render LeapsRecommendations::PageComponent.new(
      symbol:         @symbol,
      candidates:     @candidates,
      recommendation: @recommendation,
      flow_panel:     @flow_panel,
      scrape_status:  @scrape_status,
      scrape_errors:  @scrape_errors,
      user_strike:    @user_strike
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

    if fresh_data_exists?(symbol)
      return render json: { status: "ready", symbol: symbol, user_strike: user_strike }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("leaps_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
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

  def fresh_data_exists?(symbol)
    LeapsOptionChainSnapshot.for_symbol(symbol).fresh.exists?
  end

  def cached_errors(symbol)
    Array(Rails.cache.read("leaps_last_errors_#{symbol}"))
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
