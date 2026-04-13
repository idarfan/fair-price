# frozen_string_literal: true

class OwnershipController < ApplicationController
  def index
    @symbols  = WatchlistItem.order(:position, :created_at).pluck(:symbol).uniq
    @selected = sanitize_symbol(params[:symbol]) || @symbols.first
    render Ownership::PageComponent.new(symbols: @symbols, selected: @selected)
  end

  def history
    ticker    = sanitize_symbol(params[:symbol])
    snapshots = service.load_history(ticker)

    render json: {
      symbol:    ticker,
      snapshots: snapshots.map { |s| serialize_snapshot(s) }
    }
  end

  def fetch
    ticker = sanitize_symbol(params[:symbol])
    data   = YahooFinanceService.new.holders(ticker) ||
             SecEdgarService.new.holders(ticker)

    unless data
      render json: { error: "無法取得 #{ticker} 的持股資料" }, status: :unprocessable_content
      return
    end

    snapshot = service.save_snapshot(ticker, data)
    render json: serialize_snapshot(snapshot), status: :created
  end

  private

  def service = OwnershipSnapshotService.new

  def sanitize_symbol(sym)
    sym.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10).presence
  end

  def serialize_snapshot(s)
    {
      quarter:           s.quarter,
      date:              s.snapshot_date,
      institutional_pct: s.institutional_pct&.to_f,
      insider_pct:       s.insider_pct&.to_f,
      institution_count: s.institution_count,
      holders:           s.ownership_holders.map { |h|
        {
          name:         h.name,
          pct:          h.pct&.to_f,
          value:        h.market_value,
          filing_date:  h.filing_date
        }
      }
    }
  end
end
