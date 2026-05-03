# frozen_string_literal: true

class Api::IvAnalysisController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/iv_analysis
  def create
    ticker      = params[:ticker].to_s.upcase.strip
    strike      = params[:strike].to_f
    expiry_date = params[:expiry_date].to_s
    option_type = params[:option_type].to_s.downcase

    missing = []
    missing << "ticker"      if ticker.blank?
    missing << "strike"      if params[:strike].blank?
    missing << "expiry_date" if expiry_date.blank?
    missing << "option_type" if option_type.blank?

    return render json: { error: "missing fields: #{missing.join(', ')}" }, status: :unprocessable_entity if missing.any?

    begin
      detail = IvSidecarService.fetch_option_detail(
        ticker:      ticker,
        strike:      strike,
        expiry_date: expiry_date,
        option_type: option_type
      )
    rescue IvSidecarService::UnavailableError => e
      return render json: { error: e.message }, status: :service_unavailable
    rescue IvSidecarService::RequestError => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    WatchedTickersService.add(ticker)

    stats = IvStatsService.calculate(ticker, detail[:iv])

    low_iv_signal, notice = build_signal(stats)

    query = IvQuery.create!(
      ticker:         ticker,
      strike:         detail[:strike],
      expiry_date:    expiry_date,
      option_type:    option_type,
      current_price:  detail[:current_price],
      delta:          detail[:delta],
      iv:             detail[:iv],
      ivr_1y:         stats.ivr_1y,
      ivp_1y:         stats.ivp_1y,
      ivr_2y:         stats.ivr_2y,
      ivp_2y:         stats.ivp_2y,
      available_days: stats.available_days,
      data_quality:   stats.data_quality,
      low_iv_signal:  low_iv_signal,
      queried_at:     Time.current
    )

    render json: {
      ticker:         query.ticker,
      strike:         query.strike,
      expiry_date:    query.expiry_date,
      option_type:    query.option_type,
      current_price:  query.current_price,
      delta:          query.delta,
      iv:             query.iv,
      ivr_1y:         query.ivr_1y,
      ivp_1y:         query.ivp_1y,
      ivr_2y:         query.ivr_2y,
      ivp_2y:         query.ivp_2y,
      available_days: query.available_days,
      data_quality:   query.data_quality,
      low_iv_signal:  query.low_iv_signal,
      notice:         notice,
      queried_at:     query.queried_at
    }
  end

  # GET /api/iv_analysis/watchlist
  def watchlist
    watched = WatchedTicker.active.order(added_at: :desc).to_a

    # Parallel live price + IV fetch (HTTP only — no AR inside threads)
    live_prices = {}
    watched.map { |wt|
      Thread.new {
        begin
          [wt.ticker, IvSidecarService.fetch_atm_iv(wt.ticker)]
        rescue StandardError
          [wt.ticker, nil]
        end
      }
    }.each { |t| r = t.value; live_prices[r[0]] = r[1] }

    tickers = watched.map do |wt|
      snaps          = IvDailySnapshot.for_ticker(wt.ticker).ordered
      available_days = snaps.count
      data_quality   = IvStatsService.quality_for(available_days)

      live            = live_prices[wt.ticker]
      latest_query    = IvQuery.where(ticker: wt.ticker).order(queried_at: :desc).first
      intrinsic_value = nil
      time_value      = nil
      query_label     = nil

      if latest_query
        s     = live ? live[:current_price].to_f : latest_query.current_price.to_f
        sigma = live ? live[:atm_iv].to_f        : latest_query.iv.to_f
        k     = latest_query.strike.to_f
        days  = (latest_query.expiry_date.to_date - Date.today).to_i
        t     = [days.to_f / 365, 0].max

        iv_val = latest_query.option_type == "call" ? [s - k, 0].max : [k - s, 0].max
        tv_val = t > 0 ? (0.4 * s * sigma * Math.sqrt(t)).round(2) : 0.0

        intrinsic_value = iv_val.round(2)
        time_value      = tv_val
        query_label     = "#{latest_query.option_type.upcase} #{latest_query.strike} #{latest_query.expiry_date}"
      end

      {
        ticker:          wt.ticker,
        added_at:        wt.added_at,
        last_fetched_at: wt.last_fetched_at,
        available_days:  available_days,
        latest_atm_iv:   live ? live[:atm_iv] : snaps.last&.atm_iv,
        data_quality:    data_quality.to_s,
        intrinsic_value: intrinsic_value,
        time_value:      time_value,
        query_label:     query_label,
        is_live:         live != nil
      }
    end

    render json: { watchlist: tickers }
  end

  # DELETE /api/iv_analysis/watchlist/:ticker
  def watchlist_destroy
    ticker = params[:ticker].to_s.upcase.strip
    WatchedTickersService.remove(ticker)
    render json: { success: true }
  end

  private

  def build_signal(stats)
    if stats.available_days < 30
      return [false, "資料累積不足 #{stats.available_days} 天，IVR/IVP 尚不可靠"]
    end

    low    = (stats.ivr_1y && stats.ivr_1y < 20) || (stats.ivr_2y && stats.ivr_2y < 20)
    notice = stats.data_quality == "limited" ? "資料累積中（#{stats.available_days} 天），建議等待更多歷史資料" : nil
    [low, notice]
  end
end
