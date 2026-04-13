# frozen_string_literal: true

class Api::V1::OptionSnapshotsController < Api::V1::BaseController
  # GET /api/v1/option_snapshots/:symbol
  # params: type (put|call), days (integer), expiration (date)
  def index
    ticker = find_ticker
    return render json: { error: "找不到追蹤代號 #{params[:symbol].upcase}" }, status: :not_found unless ticker

    # 所有可用快照日期（新到舊）
    available_dates = ticker.option_snapshots
                            .distinct
                            .order(snapshot_date: :desc)
                            .pluck(:snapshot_date)
                            .map(&:to_s)

    # 決定要查哪一天
    target_date = if params[:snapshot_date].present? && available_dates.include?(params[:snapshot_date])
                    params[:snapshot_date]
    else
                    available_dates.first
    end

    if target_date
      # DISTINCT ON：每個合約只取該日期內 snapped_at 最新一筆
      scope = ticker.option_snapshots
                    .where(snapshot_date: target_date)
                    .select("DISTINCT ON (contract_symbol) option_snapshots.*")
                    .order("contract_symbol, snapped_at DESC")

      expirations = ticker.option_snapshots
                          .where(snapshot_date: target_date)
                          .distinct.order(:expiration).pluck(:expiration)
    else
      scope       = OptionSnapshot.none
      expirations = []
    end

    render json: {
      symbol:               ticker.symbol,
      snapshots:            scope.map { |s| serialize_snapshot(s) },
      expirations:          expirations,
      latest_snapshot_date: target_date,
      available_dates:      available_dates
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
