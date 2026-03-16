# frozen_string_literal: true

class OwnershipController < ApplicationController
  def index
    @symbols  = PriceAlert.order(:position, :created_at).pluck(:symbol).uniq
    @selected = sanitize_symbol(params[:symbol]) || @symbols.first
    render Ownership::PageComponent.new(symbols: @symbols, selected: @selected)
  end

  def history
    symbol    = sanitize_symbol(params[:symbol])
    snapshots = OwnershipSnapshot.history_for(symbol, limit: 30)

    render json: {
      symbol:    symbol,
      snapshots: snapshots.map { |s| serialize_snapshot(s) }
    }
  end

  def fetch
    symbol = sanitize_symbol(params[:symbol])
    data   = YahooFinanceService.new.holders(symbol) ||
             SecEdgarService.new.holders(symbol)

    unless data
      render json: { error: "無法取得 #{symbol} 的持股資料" }, status: :unprocessable_content
      return
    end

    summary  = data[:summary] || {}
    snapshot = OwnershipSnapshot.create!(
      symbol:                 symbol,
      fetched_at:             Time.current,
      institutions_pct:       summary[:institutions_pct],
      insiders_pct:           summary[:insiders_pct],
      institutions_float_pct: summary[:institutions_float_pct],
      institutions_count:     summary[:institutions_count],
      top_holders:            data[:top_holders] || [],
      source:                 data[:source]
    )

    render json: serialize_snapshot(snapshot), status: :created
  end

  private

  def sanitize_symbol(sym)
    sym.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10).presence
  end

  def serialize_snapshot(s)
    {
      id:                     s.id,
      fetched_at:             s.fetched_at.iso8601,
      institutions_pct:       s.institutions_pct&.to_f,
      insiders_pct:           s.insiders_pct&.to_f,
      institutions_float_pct: s.institutions_float_pct&.to_f,
      institutions_count:     s.institutions_count,
      top_holders:            s.top_holders,
      source:                 s.source
    }
  end
end
