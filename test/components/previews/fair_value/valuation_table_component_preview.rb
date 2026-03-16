# frozen_string_literal: true

# @label Valuation Table
class FairValue::ValuationTableComponentPreview < Lookbook::Preview
  layout "component_preview"

  SAMPLE_VALUATIONS = [
    {
      method:  "DCF",
      value:   197.83,
      note:    "FCF r=10.0% g=8.9%",
      formula: "FCF/股=$7.37 → 預測5年(g=8.9%) + 終端價值(gt=3.0%) → 折現(r=10.0%)"
    },
    {
      method:  "P/E",
      value:   225.05,
      note:    "EPS $6.43 × 35x",
      formula: "Trailing EPS $6.43 × Technology 平均 P/E 35x = $225.05"
    },
    {
      method:  "PEG",
      value:   572.27,
      note:    "PEG=1 公允價（當前PEG=3.73）",
      formula: "公式：P/E ÷ g% → PEG=1時 公允P/E=89x → $6.43 × 89 = $572.27"
    }
  ].freeze

  # @label Default (highlight first row)
  # @param current_price number
  # @param show_formulas toggle
  # @param highlight_first toggle
  def default(current_price: 213.32, show_formulas: false, highlight_first: true)
    render FairValue::ValuationTableComponent.new(
      valuations: SAMPLE_VALUATIONS,
      current_price:,
      show_formulas:,
      highlight_first:,
      caption: "估值方法彙整"
    )
  end

  # @label With formulas expanded
  def with_formulas
    render FairValue::ValuationTableComponent.new(
      valuations: SAMPLE_VALUATIONS,
      current_price: 213.32,
      show_formulas: true
    )
  end

  # @label Financial stock (Excess Returns + P/E + P/B)
  def financial_stock
    valuations = [
      { method: "ExcessRet", value: 42.50,  note: "ROE 12.3%", formula: "BV $35 + (ROE 12.3% − CoE 10.0%) × BV ÷ (CoE−g)" },
      { method: "P/E",       value: 38.25,  note: "EPS $2.55 × 15x", formula: "EPS × 15x" },
      { method: "P/B",       value: 52.50,  note: "BVPS $35 × 1.5x", formula: "BVPS × 1.5x" }
    ]
    render FairValue::ValuationTableComponent.new(valuations:, current_price: 45.0, caption: "金融股估值")
  end
end
