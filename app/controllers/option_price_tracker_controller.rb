# frozen_string_literal: true

class OptionPriceTrackerController < ApplicationController
  def index
    @tracked_tickers = TrackedTickerSerializer.list(TrackedTicker.order(:symbol))
    # tracked_tickers 是共用的蒐集設定，只有 admin 能改動
    # （見 Api::V1::TrackedTickersController#require_admin!）。
    # 前端拿這個旗標把新增/移除收起來——不傳的話非 admin 會看到按鈕、
    # 按下去只拿到一句「新增失敗」，看起來像壞掉而不是權限限制。
    @can_manage_tickers = current_user&.admin? || false
  end
end
