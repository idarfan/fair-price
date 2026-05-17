# frozen_string_literal: true

class IvWatchlistsController < ApplicationController
  def index
    @grouped  = IvWatchlist.active.by_group.group_by(&:group_tag)
    @new_item = IvWatchlist.new
    render IvWatchlists::IndexView.new(grouped: @grouped, new_item: @new_item)
  end

  def chart_data
    symbol = params[:symbol].to_s.upcase.strip
    days   = (params[:days] || 90).to_i.clamp(7, 365)

    rows = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT
        to_char(s.snapshot_date, 'YYYY-MM-DD') AS date,
        ROUND(s.put_iv_025  * 100, 2)          AS put_iv,
        ROUND(s.call_iv_025 * 100, 2)          AS call_iv,
        ROUND(s.skew_pts::numeric,  2)          AS skew,
        d.current_price                         AS stock_price
      FROM skew_rank_daily s
      LEFT JOIN iv_daily_snapshots d
        ON d.ticker = s.ticker AND d.snapshot_date = s.snapshot_date
      WHERE s.ticker = #{ActiveRecord::Base.connection.quote(symbol)}
        AND s.snapshot_date >= CURRENT_DATE - INTERVAL '#{days} days'
      ORDER BY s.snapshot_date ASC
    SQL

    if rows.ntuples.zero?
      render json: { error: "no_data", symbol: symbol }
      return
    end

    skews  = rows.map { |r| r["skew"].to_f }
    sorted = skews.sort
    p75_idx = [ (sorted.size * 0.75).ceil - 1, 0 ].max
    p75    = sorted[p75_idx].round(2)

    render json: {
      symbol:  symbol,
      p75:     p75,
      labels:  rows.map { |r| r["date"] },
      put_iv:  rows.map { |r| r["put_iv"].to_f },
      call_iv: rows.map { |r| r["call_iv"].to_f },
      skew:    rows.map { |r| r["skew"].to_f },
      price:   rows.map { |r| r["stock_price"].to_f }
    }
  end

  def create
    @item = IvWatchlist.new(watchlist_params)
    if @item.save
      respond_to do |format|
        format.html { redirect_to iv_watchlists_path, notice: "#{@item.symbol} 已加入追蹤清單" }
        format.json { render json: { success: true, item: @item } }
      end
    else
      respond_to do |format|
        format.html { redirect_to iv_watchlists_path, alert: @item.errors.full_messages.join(", ") }
        format.json { render json: { success: false, errors: @item.errors.full_messages }, status: 422 }
      end
    end
  end

  def destroy
    @item  = IvWatchlist.find(params[:id])
    symbol = @item.symbol
    @item.destroy
    respond_to do |format|
      format.html { redirect_to iv_watchlists_path, notice: "#{symbol} 已移除" }
      format.json { render json: { success: true } }
    end
  end

  def toggle
    @item = IvWatchlist.find(params[:id])
    @item.update(active: !@item.active)
    render json: { success: true, active: @item.active }
  end

  private

  def watchlist_params
    params.require(:iv_watchlist).permit(:symbol, :group_tag)
  end
end
