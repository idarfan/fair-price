# frozen_string_literal: true

class LeapsRecommendationsController < ApplicationController
  include CdpPrecheckable
  def index
    @symbol        = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    @candidates    = []
    @flow_panel    = nil
    @scrape_status = nil
    @scrape_errors = []

    @user_strike = params[:user_strike].presence

    if @symbol.present?
      if fresh_data_exists?(@symbol, user_strike: @user_strike&.to_f)
        @candidates    = LeapsRankingService.new(@symbol).call
        @recommendation = LeapsRecommendationService.new(@candidates).call
        @flow_panel     = LeapsOptionsFlowPanelService.new(@symbol, @candidates).call

        @scrape_status = :cached

        case params[:job_status]
        when "session_expired"
          @scrape_status = :session_expired
        when "cdp_offline"
          @scrape_status = :cdp_offline
        when "partial_error"
          @scrape_status = :partial_error
          @scrape_errors = cached_errors(@symbol)
        when "error"
          @scrape_status = :error
          @scrape_errors = cached_errors(@symbol)
        when "no_candidates"
          @scrape_status = :no_candidates
        when "invalid_strike"
          @scrape_status = :invalid_strike
          @scrape_errors = cached_errors(@symbol)
        end

        # When analyze returned "ready" (no job_status forwarded) but candidates
        # are empty, determine the correct status from the last cached error state.
        if @candidates.empty? && @scrape_status == :cached
          last_errors = cached_errors(@symbol)
          if last_errors.any?
            @scrape_status = :partial_error
            @scrape_errors = last_errors
          else
            @scrape_status = :no_candidates
          end
        end
      elsif params[:job_status].present?
        case params[:job_status]
        when "session_expired"
          @scrape_status = :session_expired
        when "cdp_offline"
          @scrape_status = :cdp_offline
        when "no_candidates"
          @scrape_status = :no_candidates
        when "partial_error"
          @scrape_status = :partial_error
          @scrape_errors = cached_errors(@symbol)
        when "invalid_strike"
          @scrape_status = :invalid_strike
          @scrape_errors = cached_errors(@symbol)
        when "success", "cached"
          # 工作回報成功、但資料不 fresh。可能是零候選，或這次抓的中心履約價
          # 與網址上的 user_strike 對不上。**這不是「未知錯誤」**——
          # 2026-09-01 使用者實際踩到：NOK 履約價 5 抓完之後畫面顯示
          # 「抓取時發生未知錯誤」，其實 job 是 success。
          # 同 feedback_scraper_status_case 的教訓：狀態沒列進 case 就會
          # 掉到 else，只是這次掉錯方向（成功被當成錯誤）。
          errors = cached_errors(@symbol)
          if errors.any?
            @scrape_status = :partial_error
            @scrape_errors = errors
          else
            @scrape_status = :no_candidates
          end
        else
          @scrape_status = :error
          @scrape_errors = cached_errors(@symbol)
        end
      else
        @scrape_status = :ready_to_fetch
      end
    end

    # 推薦分析圖卡的 {latest_earnings}：唯讀既有 fundamentals（Barchart overview 抓取），
    # 不新增 service、不打外部 API；無資料時 component 端降級顯示。
    next_earnings = @symbol.present? ?
      Fundamental.where(symbol: @symbol).order(:updated_at).last&.next_earnings_date : nil

    @pmcc_ranking = pmcc_ranking_for(@symbol, @candidates)
    @pmcc_tracker = pmcc_tracker_for(@symbol)

    render LeapsRecommendations::PageComponent.new(
      symbol:         @symbol,
      candidates:     @candidates,
      recommendation: @recommendation,
      flow_panel:     @flow_panel,
      scrape_status:  @scrape_status,
      scrape_errors:  @scrape_errors,
      user_strike:    @user_strike,
      next_earnings:  next_earnings,
      pmcc_ranking:   @pmcc_ranking,
      pmcc_tracker:   @pmcc_tracker
    )
  end

  def analyze
    symbol = params[:symbol]&.upcase&.strip&.gsub(/[^A-Z0-9.\-]/, "")
    return render json: { error: "symbol required" }, status: :unprocessable_entity if symbol.blank?

    user_strike = nil
    if params[:user_strike].present?
      raw = params[:user_strike].to_s.strip
      if raw.match?(/\A\d+(\.\d{1,2})?\z/) && raw.to_f > 0
        user_strike = raw.to_f
      else
        return render json: { error: "user_strike 必須是正數（最多兩位小數）" }, status: :unprocessable_entity
      end
    end

    # Controller-layer snapshot validation (fast path — no scrape needed)
    if user_strike
      snap = StrikeChainSnapshot.find_by(symbol: symbol)
      if snap && !snap.valid_strike?(user_strike)
        return render json: {
          status:  "invalid_strike",
          message: snap.invalid_message(symbol, user_strike)
        }
      end
    end

    if fresh_data_exists?(symbol, user_strike: user_strike)
      return render json: { status: "ready", symbol: symbol, user_strike: user_strike }
    end

    unless cdp_online?
      return render json: { status: "cdp_offline" }
    end

    job_id = SecureRandom.hex(8)
    Rails.cache.write("leaps_job_#{job_id}", { status: "pending" }, expires_in: LeapsOptionChainSnapshot::FRESH_WINDOW)
    ScrapeLeapsJob.perform_later(symbol, job_id, user_strike: user_strike)

    render json: { job_id: job_id, symbol: symbol, user_strike: user_strike }
  end

  def status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", error: "missing job_id" }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read("leaps_job_#{job_id}")
    render json: cached || { status: "not_found" }
  end

  private

  # 判斷邏輯唯一定義在 LeapsOptionChainSnapshot.fresh_for?（時間新鮮 +
  # 中心履約價吻合），這裡跟 BarchartScraperService#fetch_leaps 內部的
  # cache 短路都呼叫同一個方法，避免兩處各自維護一份、又漂移出不一致。
  def fresh_data_exists?(symbol, user_strike: nil)
    LeapsOptionChainSnapshot.fresh_for?(symbol, user_strike: user_strike)
  end

  def cached_errors(symbol)
    Array(Rails.cache.read("leaps_last_errors_#{symbol}"))
  end

  # PMCC v3 §8：只有 LEAPS 排行有候選、且該 symbol 曾抓過 Short Call 資料時
  # 才跑純計算的 PmccRankingService；否則回傳 :no_data，component 端據此顯示
  # 「尚無資料」而不是硬跑一次空計算。PMCC 計算本身不打 Barchart、不寫 DB，
  # 失敗只可能是資料本身缺失（有 PmccRankingService 自己的 :no_leaps/:no_short
  # 分支），這裡不需要額外 rescue。
  def pmcc_ranking_for(symbol, candidates)
    return { status: :no_data } if symbol.blank? || candidates.blank?
    return { status: :no_data } unless PmccShortCallSnapshot.for_symbol(symbol).exists?

    PmccRankingService.new(symbol).call
  end

  # 部位追蹤：**刻意不看 candidates**。這是使用者自己的持久資料，不該因為
  # 當下抓取沒有候選（或 Barchart 掛了）就從畫面消失——這點與
  # pmcc_ranking_for 的 `candidates.blank? -> :no_data` 是不同語意。
  #
  # 一律從 current_user 出發（比照 Api::V1::MarginPositionsController），
  # 別人的部位查不到。
  def pmcc_tracker_for(symbol)
    return nil if symbol.blank? || current_user.blank?

    position = current_user.pmcc_positions.active_positions.for_symbol(symbol).first
    return nil if position.blank?

    open_leg = position.open_short_leg
    quote    = short_leg_quote(symbol, open_leg)

    {
      position:    position,
      pnl:         PmccPnlService.call(position),
      trigger:     open_leg && PmccRollTriggerService.call(open_leg, quote: quote),
      suggestions: PmccRollSuggestionService.call(
        position,
        candidates:    PmccShortCallSnapshot.for_symbol(symbol).to_a,
        current_quote: quote
      )
    }
  end

  # 目前這一腳短腳的最新報價（買回成本 + 觸發判斷都要用）
  def short_leg_quote(symbol, open_leg)
    return nil if open_leg.blank?

    PmccShortCallSnapshot.for_symbol(symbol)
                         .find_by(expiration_date: open_leg.short_expiration,
                                  strike: open_leg.short_strike)
  end
end
