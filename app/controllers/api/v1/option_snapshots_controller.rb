# frozen_string_literal: true

class Api::V1::OptionSnapshotsController < ApplicationController
  # GET /api/v1/option_snapshots/:symbol
  # params: type (put|call), days (integer), expiration (date)
  def index
    ticker = find_ticker
    return render json: { error: "找不到追蹤代號 #{params[:symbol].upcase}" }, status: :not_found unless ticker

    days  = (params[:days] || 60).to_i.clamp(1, 90)
    scope = ticker.option_snapshots.recent_days(days).order(:expiration, :strike)
    scope = scope.where(option_type: params[:type]) if %w[put call].include?(params[:type])
    scope = scope.where(expiration: params[:expiration]) if params[:expiration].present?

    if params[:latest_only] == "true"
      latest_date = ticker.option_snapshots.maximum(:snapshot_date)
      if latest_date
        # DISTINCT ON: 每個合約只取 snapped_at 最新的一筆
        scope = ticker.option_snapshots
                      .where(snapshot_date: latest_date)
                      .select("DISTINCT ON (contract_symbol) option_snapshots.*")
                      .order("contract_symbol, snapped_at DESC")
      end
    end

    base        = ticker.option_snapshots.recent_days(days)
    expirations = base.where(snapshot_date: base.maximum(:snapshot_date))
                      .distinct.order(:expiration).pluck(:expiration)

    render json: {
      symbol:             ticker.symbol,
      snapshots:          scope.map { |s| serialize_snapshot(s) },
      expirations:        expirations,
      latest_snapshot_date: ticker.option_snapshots.maximum(:snapshot_date)
    }
  end

  # GET /api/v1/option_snapshots/:symbol/premium_trend
  # params: contract_symbol OR (strike + expiration + type)
  #         hours=N — return only the last N hours of data (e.g. hours=30 for yesterday's session)
  def premium_trend
    ticker = find_ticker
    return render json: { error: "找不到追蹤代號 #{params[:symbol].upcase}" }, status: :not_found unless ticker

    scope = if params[:contract_symbol].present?
              ticker.option_snapshots
                    .where(contract_symbol: params[:contract_symbol])
    else
              OptionSnapshot.where(
                tracked_ticker_id: ticker.id,
                strike:            params[:strike].to_f,
                expiration:        params[:expiration],
                option_type:       params[:type] || "put"
              )
    end

    # Intraday filter: last N hours (e.g. hours=36 covers yesterday's US session)
    if params[:hours].present?
      cutoff = params[:hours].to_i.clamp(1, 168).hours.ago
      scope = scope.where("snapped_at >= ?", cutoff)
    end

    rows = scope.order(:snapped_at)

    render json: rows.map { |s|
      {
        date:               s.snapshot_date,
        snapped_at:         s.snapped_at&.utc&.iso8601(0),
        bid:                s.bid&.to_f,
        ask:                s.ask&.to_f,
        last_price:         s.last_price&.to_f,
        implied_volatility: s.implied_volatility&.to_f,
        volume:             s.volume,
        open_interest:      s.open_interest,
        underlying_price:   s.underlying_price&.to_f
      }
    }
  end

  private

  def find_ticker
    TrackedTicker.find_by(symbol: params[:symbol].to_s.upcase)
  end

  def serialize_snapshot(s)
    {
      id:                 s.id,
      contract_symbol:    s.contract_symbol,
      option_type:        s.option_type,
      expiration:         s.expiration,
      strike:             s.strike.to_f,
      bid:                s.bid&.to_f,
      ask:                s.ask&.to_f,
      last_price:         s.last_price&.to_f,
      implied_volatility: s.implied_volatility&.to_f,
      volume:             s.volume,
      open_interest:      s.open_interest,
      in_the_money:       s.in_the_money,
      underlying_price:   s.underlying_price&.to_f,
      snapshot_date:      s.snapshot_date
    }
  end
end
