# frozen_string_literal: true

# @label Methodology Note
class FairValue::MethodologyNoteComponentPreview < Lookbook::Preview
  layout "component_preview"

  SAMPLE_METHODS_GENERAL = [
    {
      method: "DCF", value: 195.32, note: "FCF r=10.0% g=8.9%",
      formula: "FCF/股=$7.37 → 預測5年(g=8.9%) + 終端價值(gt=3.0%) → 折現(r=10.0%)",
      rationale: "以企業未來自由現金流（FCF）逐年折現加總，反映最純粹的內在價值。輸入：FCF/股、預測期成長率 g、折現率 r（必要報酬率）、終端成長率 gt。"
    },
    {
      method: "P/E", value: 225.05, note: "EPS $6.43 × 35x",
      formula: "Trailing EPS $6.43 × Technology 平均 P/E 35x = $225.05",
      rationale: "以產業平均本益比（P/E）乘以每股盈餘（EPS），反映市場對同類公司的定價水準。優點：直觀、廣泛使用；缺點：不納入成長性，高成長公司往往被低估。"
    },
    {
      method: "PEG", value: 572.27, note: "PEG=1 公允價（當前PEG=3.73）",
      formula: "公式：P/E ÷ g% → PEG=1時 公允P/E=89x → $6.43 × 89 = $572.27",
      rationale: "在 P/E 基礎上調整成長率：PEG = P/E ÷ EPS成長率%。PEG = 1 視為公允價值，<1 代表相對便宜、>1 代表成長溢價。"
    }
  ].freeze

  # @label 一般股（預設展開）
  # @param expanded toggle "預設展開"
  # @param growth_rate number "成長率（小數，0.089 = 8.9%）"
  def general_stock(expanded: true, growth_rate: 0.089)
    render FairValue::MethodologyNoteComponent.new(
      stock_type:           "一般股",
      stock_type_rationale: "公司 EPS 為正且無特殊產業屬性，採主流三法估值：① DCF 現金流折現（核心內在價值，最全面）② P/E 本益比（市場最廣泛使用的相對估值）③ PEG 成長調整本益比（將成長速度納入定價，PEG=1 為公允）。",
      valuation_methods:    SAMPLE_METHODS_GENERAL,
      growth_rate:          growth_rate,
      growth_rate_note:     "盈餘成長(YoY)、營收成長",
      expanded:             expanded
    )
  end

  # @label 金融股
  def financial_stock
    render FairValue::MethodologyNoteComponent.new(
      stock_type:           "金融股",
      stock_type_rationale: "銀行保險業資本結構特殊，自由現金流難以直接衡量，採：① Excess Returns Model ② P/E 本益比 ③ P/B 帳面價值倍數。",
      valuation_methods: [
        { method: "ExcessRet", value: 42.50, note: "ROE 12.3%",
          formula: "BV $35 + (ROE 12.3% − CoE 10.0%) × BV ÷ (CoE−g)",
          rationale: "衡量 ROE 超過股東要求報酬率所創造的超額價值，適合金融業。" }
      ],
      growth_rate: 0.04,
      expanded:    true
    )
  end

  # @label 週期股（摺疊）
  def cyclical_stock
    render FairValue::MethodologyNoteComponent.new(
      stock_type:           "週期股",
      stock_type_rationale: "週期性產業盈餘受景氣循環大幅波動，不宜以當期 EPS 定價，採 EV/EBITDA、P/B、DCF 三法。",
      valuation_methods: [
        { method: "EV/EBITDA", value: 137.81, note: "× 8x",
          formula: "EBITDA × 8x(Consumer Cyclical) − 淨負債 ÷ 流通股數",
          rationale: "排除資本結構差異與折舊攤銷，是週期股最穩健的估值。" },
        { method: "P/B", value: 81.13, note: "BVPS $67.61 × 1.2x",
          formula: "每股淨值 $67.61 × 1.2x",
          rationale: "以帳面每股淨值乘以產業平均 P/B 倍數，反映資產品質評價。" }
      ],
      growth_rate: 0.03,
      expanded:    false
    )
  end
end
