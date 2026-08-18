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
  include LeapsRecommendations::PmccEducation
  include LeapsRecommendations::VocabCards

  def initialize(symbol: nil, candidates: [], recommendation: nil, flow_panel: nil, scrape_status: nil, scrape_errors: [], user_strike: nil, next_earnings: nil, pmcc_ranking: nil)
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
  end


  def view_template
    div(id: "leaps-export-root", class: "space-y-6",
        data_pdf_font_url: helpers.asset_path("NotoSansTC-Regular-subset-v39.ttf"),
        data_pdf_ipa_font_url: helpers.asset_path("NotoSans-Regular-ipa-subset-v42.ttf")) do
      render_header
      render_search_form
      render_status_bar if @scrape_status
      if @candidates.any?
        render_recommendation if @recommendation
        render_ranking_table
        render_flow_panel if @flow_panel
        render_pmcc_section
      end
      render_pmcc_edu_section
      render_vocab_cards
      render_price_estimator_modal
    end
    render_pdf_data_script
    render_loading_script
  end


  private
end
