# frozen_string_literal: true

class LeapsRecommendations::PageComponent < ApplicationComponent
  include LeapsRecommendations::Formatting
  include LeapsRecommendations::PageHeader
  include LeapsRecommendations::PdfExport
  include LeapsRecommendations::ConceptCards
  include LeapsRecommendations::RankingTable
  include LeapsRecommendations::PriceEstimator
  include LeapsRecommendations::FlowPanel
  include LeapsRecommendations::PmccSection
  include LeapsRecommendations::PmccPositionTracker
  include LeapsRecommendations::PmccEducation
  include LeapsRecommendations::VocabCards

  def initialize(symbol: nil, candidates: [], recommendation: nil, flow_panel: nil, scrape_status: nil, scrape_errors: [], user_strike: nil, next_earnings: nil, pmcc_ranking: nil, pmcc_tracker: nil, price_context: nil)
    @symbol         = symbol
    @candidates     = Array(candidates)
    @recommendation = recommendation
    @flow_panel     = flow_panel
    @scrape_status  = scrape_status
    @scrape_errors  = Array(scrape_errors)
    @user_strike    = user_strike
    @next_earnings  = next_earnings
    # PMCC v3 §9：render_pmcc_section／render_pmcc_edu_section 見 Step7；
    # 這裡先接住參數，讓 Step6 controller 改動不會因為未知 kwarg 直接炸掉。
    @pmcc_ranking   = pmcc_ranking
    # 部位追蹤刻意放在 candidates 判斷之外：這是使用者的持久資料，
    # 抓取失敗時不該跟著消失（見 controller 的 pmcc_tracker_for）。
    @pmcc_tracker   = pmcc_tracker
    # 三個價格情境 widget 的資料。首次載入時通常是 nil（還沒抓），
    # 畫面先出骨架，由 leapsPriceContext.ts 輪詢 /leaps/price_context 換上來。
    @price_context  = price_context
  end


  def view_template
    div(id: "leaps-export-root", class: "space-y-6",
        data_pdf_font_url: helpers.asset_path("NotoSansTC-Regular-subset-v39.ttf"),
        data_pdf_ipa_font_url: helpers.asset_path("NotoSans-Regular-ipa-subset-v42.ttf")) do
      render_header
      render_search_form
      render_status_bar if @scrape_status
      render_price_context
      if @candidates.any?
        render_recommendation if @recommendation
        render_ranking_table
        render_flow_panel if @flow_panel
        render_vertical_spread_frame
        render_pmcc_section
      end
      # 垂直價差只看「有沒有輸入標的與價格」，不跟候選排行綁在一起；沒有候選時
      # PMCC 不出現，外框就出現在 PMCC 原本的位置（leaps-call-spread-spec 功能定義 0）。
      render_vertical_spread_frame unless @candidates.any?
      render_pmcc_position_tracker
      render_pmcc_edu_section
      render_vocab_cards
      render_price_estimator_modal
    end
    render_pdf_data_script
    render_loading_script
  end


  private

  def render_vertical_spread_frame
    return unless @symbol.present? && @user_strike.present?

    render LeapsRecommendations::VerticalSpreadFrame.new(symbol: @symbol, user_strike: @user_strike.to_s.strip)
  end

  # 三個價格情境 widget。外層 div 是輪詢的錨點，內容由
  # PriceContextComponent 渲染；TS 拿到新 HTML 後整塊換掉 innerHTML。
  def render_price_context
    return if @symbol.blank?

    div(id: "leaps-price-context",
        data: { behavior: "leaps-price-context",
                symbol: @symbol,
                user_strike: @user_strike.to_s }) do
      render LeapsRecommendations::PriceContextComponent.new(payload: @price_context)
    end
  end
end
