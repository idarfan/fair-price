# frozen_string_literal: true

class TechnicalDashboardsController < ApplicationController
  FRESH_WINDOW = 5.minutes

  def index
    @symbol        = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    @result        = nil
    @scrape_status = nil
    @scrape_errors = []

    if @symbol.present?
      if fresh_data_exists?(@symbol)
        @result        = CompositeSignalService.new(@symbol).call
        @scrape_status = :cached
      else
        scrape = BarchartScraperService.new(@symbol).call

        case scrape[:status]
        when "barchart_session_expired"
          @scrape_status = :session_expired
        when "success", "partial_error"
          @result        = CompositeSignalService.new(@symbol).call
          @scrape_status = :fetched
          @scrape_errors = scrape[:errors]
        else
          @scrape_status = :error
          @scrape_errors = scrape[:errors]
        end
      end
    end

    render TechnicalDashboard::PageComponent.new(
      symbol:        @symbol,
      result:        @result,
      scrape_status: @scrape_status,
      scrape_errors: @scrape_errors,
    )
  end

  private

  def fresh_data_exists?(symbol)
    FetchLog.where(symbol: symbol, status: "success")
            .where("fetched_at > ?", FRESH_WINDOW.ago)
            .exists?
  end
end
