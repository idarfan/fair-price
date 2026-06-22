# frozen_string_literal: true

class TechnicalDashboardsController < ApplicationController
  FRESH_WINDOW = 1.hour

  def index
    @symbol        = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    @date          = parse_date_param(params[:date]) || Date.today
    @result        = nil
    @scrape_status = nil
    @scrape_errors = []

    @recent_symbols = FetchLog.where(status: "success")
                              .where("fetched_at > ?", 7.days.ago)
                              .group(:symbol)
                              .order("MAX(fetched_at) DESC")
                              .pluck(:symbol)
                              .first(10)

    @stock_quote = @symbol.present? ? fetch_stock_quote(@symbol) : nil

    if @symbol.present?
      if fresh_data_exists?(@symbol, @date)
        @result        = CompositeSignalService.new(@symbol, date: @date).call
        @scrape_status = :cached

        # Surface job errors from the last analyze call (e.g. session expired)
        job_status = params[:job_status]
        if job_status == "session_expired"
          @scrape_status = :session_expired
        elsif job_status == "error"
          @scrape_status = :error
          @scrape_errors = [ "抓取過程發生錯誤，部分資料可能不完整" ]
        end
      elsif params[:job_status].present?
        # Job completed but no success data — show the error state
        case params[:job_status]
        when "session_expired"
          @scrape_status = :session_expired
        else
          @scrape_status = :error
          @scrape_errors = [ "抓取失敗，請確認 Barchart 連線後重試" ]
        end
      else
        @scrape_status = @date == Date.today ? :ready_to_fetch : :no_data
      end
    end

    render TechnicalDashboard::PageComponent.new(
      symbol:         @symbol,
      date:           @date,
      result:         @result,
      scrape_status:  @scrape_status,
      scrape_errors:  @scrape_errors,
      recent_symbols: @recent_symbols,
      stock_quote:    @stock_quote,
    )
  end

  def analyze
    symbol = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    date   = parse_date_param(params[:date]) || Date.today

    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?

    if fresh_data_exists?(symbol, date)
      return render json: { status: "ready", symbol: symbol, date: date.to_s }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("td_job_#{job_id}", { status: "pending" }, expires_in: 5.minutes)
    TechnicalDashboardAnalyzeJob.perform_later(symbol, date.to_s, job_id)

    render json: { job_id: job_id, symbol: symbol, date: date.to_s }
  end

  def status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", error: "missing job_id" }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read("td_job_#{job_id}")
    render json: cached || { status: "not_found" }
  end

  private

  def fresh_data_exists?(symbol, date)
    FetchLog.where(symbol: symbol, status: "success")
            .where("fetched_at > ?", FRESH_WINDOW.ago)
            .where("DATE(fetched_at) = ?", date)
            .exists?
  end

  def fetch_stock_quote(symbol)
    svc   = FinnhubService.new
    quote = svc.quote(symbol)
    return nil if quote.nil? || quote["c"].to_f.zero?
    prof  = svc.profile(symbol) || {}
    {
      price:    quote["c"].to_f,
      change:   quote["d"].to_f,
      change_p: quote["dp"].to_f,
      ts:       quote["t"].to_i,
      name:     prof["name"].to_s,
      exchange: prof["exchange"].to_s
    }
  rescue StandardError
    nil
  end

  def parse_date_param(val)
    return nil if val.blank?
    Date.parse(val)
  rescue ArgumentError, TypeError
    nil
  end
end
