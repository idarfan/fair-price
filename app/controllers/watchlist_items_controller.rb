# frozen_string_literal: true

class WatchlistItemsController < ApplicationController
  def create
    symbol = params.require(:symbol).upcase.strip
    quote  = FinnhubService.new.quote(symbol)

    unless quote && (quote["c"].to_f.positive? || quote["pc"].to_f.positive?)
      redirect_to momentum_report_path, alert: "找不到「#{symbol}」的報價，請確認代號正確"
      return
    end

    item = current_user.watchlist_items.find_or_initialize_by(symbol: symbol)
    if item.new_record?
      item.position = current_user.watchlist_items.next_position
      item.save!
    end

    redirect_to momentum_report_path
  rescue ActionController::ParameterMissing
    redirect_to momentum_report_path, alert: "請輸入股票代號"
  end

  def update
    item   = current_user.watchlist_items.find(params[:id])
    symbol = params.require(:symbol).upcase.strip
    quote  = FinnhubService.new.quote(symbol)

    unless quote && (quote["c"].to_f.positive? || quote["pc"].to_f.positive?)
      redirect_to momentum_report_path, alert: "找不到「#{symbol}」的報價，請確認代號正確"
      return
    end

    item.update!(symbol: symbol)
    redirect_to momentum_report_path
  rescue ActiveRecord::RecordNotFound
    redirect_to momentum_report_path
  end

  def destroy
    current_user.watchlist_items.find(params[:id]).destroy
    redirect_to momentum_report_path
  rescue ActiveRecord::RecordNotFound
    redirect_to momentum_report_path
  end

  def reorder
    ids = params.require(:ids)
    ids.each_with_index { |id, i| current_user.watchlist_items.where(id: id).update_all(position: i) }
    head :ok
  end
end
