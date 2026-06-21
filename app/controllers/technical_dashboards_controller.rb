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

    if @symbol.present?
      if fresh_data_exists?(@symbol, @date)
        @result        = CompositeSignalService.new(@symbol, date: @date).call
        @scrape_status = :cached
      elsif @date == Date.today
        scrape = BarchartScraperService.new(@symbol).call

        case scrape[:status]
        when "barchart_session_expired"
          @scrape_status = :session_expired
        when "success", "partial_error"
          @result        = CompositeSignalService.new(@symbol, date: @date).call
          @scrape_status = :fetched
          @scrape_errors = scrape[:errors]
        else
          @scrape_status = :error
          @scrape_errors = scrape[:errors]
        end
      else
        @scrape_status = :no_data
      end
    end

    render TechnicalDashboard::PageComponent.new(
      symbol:         @symbol,
      date:           @date,
      result:         @result,
      scrape_status:  @scrape_status,
      scrape_errors:  @scrape_errors,
      recent_symbols: @recent_symbols,
    )
  end

  private

  def fresh_data_exists?(symbol, date)
    FetchLog.where(symbol: symbol, status: "success")
            .where("fetched_at > ?", FRESH_WINDOW.ago)
            .where("DATE(fetched_at) = ?", date)
            .exists?
  end

  def parse_date_param(val)
    return nil if val.blank?
    Date.parse(val)
  rescue ArgumentError, TypeError
    nil
  end
end
