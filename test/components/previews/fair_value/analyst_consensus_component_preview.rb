# frozen_string_literal: true

# @label Analyst Consensus
class FairValue::AnalystConsensusComponentPreview < Lookbook::Preview
  layout "component_preview"

  STRONG_BUY_CONSENSUS = {
    strong_buy: 22, buy: 10, hold: 3, sell: 1, strong_sell: 0,
    total: 36, score: 4.5, rating: "強力買入", period: "2026-02"
  }.freeze

  MIXED_CONSENSUS = {
    strong_buy: 8, buy: 12, hold: 15, sell: 4, strong_sell: 2,
    total: 41, score: 3.0, rating: "持有", period: "2026-02"
  }.freeze

  BEARISH_CONSENSUS = {
    strong_buy: 1, buy: 2, hold: 8, sell: 10, strong_sell: 5,
    total: 26, score: 1.8, rating: "賣出", period: "2026-02"
  }.freeze

  # @label 強力買入（NVDA 風格）
  # @param show_score toggle "顯示評分"
  # @param show_breakdown toggle "顯示明細"
  def strong_buy(show_score: true, show_breakdown: true)
    render FairValue::AnalystConsensusComponent.new(
      consensus:      STRONG_BUY_CONSENSUS,
      symbol:         "NVDA",
      show_score:     show_score,
      show_breakdown: show_breakdown
    )
  end

  # @label 中性分歧（混合評級）
  def mixed_ratings
    render FairValue::AnalystConsensusComponent.new(
      consensus:      MIXED_CONSENSUS,
      symbol:         "INTC",
      show_score:     true,
      show_breakdown: true
    )
  end

  # @label 偏空（賣出評級）
  def bearish
    render FairValue::AnalystConsensusComponent.new(
      consensus:      BEARISH_CONSENSUS,
      symbol:         "F",
      show_score:     true,
      show_breakdown: true
    )
  end

  # @label 無資料（顯示佔位符）
  def no_data
    render FairValue::AnalystConsensusComponent.new(
      consensus: nil,
      symbol:    "XYZ"
    )
  end
end
