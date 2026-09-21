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
      pmcc_tracker:   @pmcc_tracker,
      # 已經有快照就直接畫，不必等前端輪詢一輪才看到東西。
      # 沒有就傳 nil，畫面出骨架，由 leapsPriceContext.ts 接手。
      price_context:  price_context_payload
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

  # 三個價格情境 widget 的輪詢端點。
  #
  # 回傳**渲染好的 HTML 片段**而不是原始數字：markup 與數字格式只在 Phlex 寫一份，
  # TS 端不重寫一套排版（同 pdf_export.rb 註解裡「避免兩處數字格式漂移」的理由）。
  def price_context
    symbol = params[:symbol].to_s.upcase.strip.gsub(/[^A-Z0-9.\-]/, "")
    return render json: { status: "error", message: "missing symbol" },
                  status: :unprocessable_entity if symbol.blank?

    payload = LeapsPriceContextService.new(symbol, user_strike: params[:user_strike].presence).call

    # ⚠️ gate 只看 VOLAP 那條供給線（POI／52 週同源於 VolapSnapshot），
    # **不能看「三塊任一塊有」**。day_range 走的是 DailyBar，兩條線完全獨立，
    # 而且 day_range 幾乎永遠有值——用 any? 的話每個缺 VOLAP 的代號都會被判成
    # 「已經有資料了」直接回 ok，job 一次都排不出去。
    # 2026-09-21 NOK 實際踩到：volap_snapshots 整張表只有 SHOP 一筆，
    # NOK 的 POI 與 52 週從上線起就停在「載入中…」，而且是**永遠不會結束**的載入
    # （前端收到 ok 就停止輪詢）。同 feedback_silent_guards_and_cache：
    # 一道過寬的防護把「沒抓到」偽裝成「不用抓」。
    if payload.values_at(:poi, :week52).any?(&:present?)
      return render json: { status: "ok", html: render_price_context_html(payload) }
    end

    # VOLAP 缺席。day_range 可能已經有了——那張卡要留著，不能被錯誤訊息洗掉。
    has_partial = payload[:day_range].present?
    job = Rails.cache.read(ScrapePriceContextJob.cache_key(symbol))
    terminal = price_context_terminal_message(job&.dig(:status))

    # 抓過而且確定拿不到：回終局訊息讓前端停止輪詢。
    return render json: price_context_stop(payload, has_partial, terminal) if terminal

    # CLAUDE.md「CDP 預檢（全域強制）」：排 job 之前先確認 CDP 連得上，
    # 連不上就直接回報、不排 job，讓使用者 1–2 秒內看到可行動的訊息，
    # 而不是輪詢兩分鐘才逾時。
    return render json: price_context_stop(payload, has_partial, CDP_OFFLINE_MESSAGE) unless cdp_online?

    # 用 cache lock 擋掉輪詢造成的重複排程——前端每 5 秒問一次，
    # 沒有這道鎖會排出一串重複的抓取。
    enqueue_price_context(symbol)

    # 已經有 day_range 就連同那張卡一起回，使用者不必盯著三張空卡等 VOLAP。
    render json: { status: "pending" }
             .merge(has_partial ? { html: render_price_context_html(payload) } : {})
  end

  private

  # index 用：已經有快照就直接帶進畫面。抓取本身是 job 的事，這裡只讀 DB。
  def price_context_payload
    return nil if @symbol.blank?

    payload = LeapsPriceContextService.new(@symbol, user_strike: @user_strike).call
    payload.values_at(:poi, :week52, :day_range).any?(&:present?) ? payload : nil
  rescue => e
    # 這三張卡是輔助資訊，算不出來絕不能讓整個 LEAPS 頁 500。
    Rails.logger.warn("[price_context] payload build failed for #{@symbol}: #{e.class}: #{e.message}")
    nil
  end

  def render_price_context_html(payload, empty_message: nil)
    LeapsRecommendations::PriceContextComponent
      .new(**{ payload: payload, empty_message: empty_message }.compact)
      .call
  end

  # VOLAP 抓取的終局狀態 → 使用者該做什麼。nil＝還在抓／還沒抓過，繼續等。
  # 三種原因的處置完全不同（去登入／去圖上掛指標／等一下再試），
  # 全部收斂成一句「抓取失敗」會讓人不知道該動哪裡。
  def price_context_terminal_message(job_status)
    case job_status
    when "barchart_session_expired"
      "請先登入 Barchart 後重新查詢。"
    when "no_volap_plot"
      "Barchart 的 interactive-chart 上沒有掛 Volume Profile（VOLAP）指標，" \
      "請加上後存成預設模板再重試。"
    when "error"
      "價格情境資料抓取失敗，請稍後重試。"
    end
  end

  # 停止輪詢的兩種回法。有 day_range 可看就回 partial：前端換上 HTML 之後
  # 在上面補一條提示，而不是用 replaceChildren 把已經看得到的卡片整塊洗掉。
  # 完全沒資料才回 error（那時整塊換成訊息才是對的）。
  def price_context_stop(payload, has_partial, message)
    return { status: "error", message: message } unless has_partial

    { status:  "partial",
      message: message,
      # 空卡不能再寫「載入中」——這一輪已經確定不會再有東西進來了。
      html:    render_price_context_html(payload, empty_message: "暫無資料") }
  end

  def enqueue_price_context(symbol)
    lock_key = "price_context_lock_#{symbol}"
    return if Rails.cache.exist?(lock_key)

    Rails.cache.write(lock_key, true, expires_in: 3.minutes)
    ScrapePriceContextJob.perform_later(symbol)
  rescue => e
    # 排不進去不該讓輪詢端點 500——前端會繼續輪詢，下一輪再試。
    Rails.logger.warn("[price_context] enqueue failed for #{symbol}: #{e.message}")
  end

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
