# frozen_string_literal: true

class LeapsRecommendationsController < ApplicationController
  def index
    @symbol        = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    @candidates    = []
    @flow_panel    = nil
    @scrape_status = nil
    @scrape_errors = []

    if @symbol.present?
      if fresh_data_exists?(@symbol)
        @candidates = LeapsRankingService.new(@symbol).call
        @flow_panel = LeapsOptionsFlowPanelService.new(@symbol).call

        @scrape_status = :cached

        case params[:job_status]
        when "session_expired" then @scrape_status = :session_expired
        when "error"
          @scrape_status = :error
          @scrape_errors = [ "抓取過程發生錯誤，部分資料可能不完整" ]
        end
      elsif params[:job_status].present?
        case params[:job_status]
        when "session_expired" then @scrape_status = :session_expired
        else
          @scrape_status = :error
          @scrape_errors = [ "抓取失敗，請確認 Barchart 連線後重試" ]
        end
      else
        @scrape_status = :ready_to_fetch
      end
    end

    render LeapsRecommendations::PageComponent.new(
      symbol:        @symbol,
      candidates:    @candidates,
      flow_panel:    @flow_panel,
      scrape_status: @scrape_status,
      scrape_errors: @scrape_errors
    )
  end

  def analyze
    symbol = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?

    if fresh_data_exists?(symbol)
      return render json: { status: "ready", symbol: symbol }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("leaps_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    ScrapeLeapsJob.perform_later(symbol, job_id)

    render json: { job_id: job_id, symbol: symbol }
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
end
