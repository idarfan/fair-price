# frozen_string_literal: true

class IvWatchlistsController < ApplicationController
  def index
    @grouped  = IvWatchlist.active.by_group.group_by(&:group_tag)
    @new_item = IvWatchlist.new
    render IvWatchlists::IndexView.new(grouped: @grouped, new_item: @new_item)
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
