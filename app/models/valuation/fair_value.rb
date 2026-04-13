# frozen_string_literal: true

module Valuation
  # ── Module-level constants ─────────────────────────────────────
  # Defined here so Classifier + ValuationMethods can reference them
  # by bare name through lexical scope (both modules are nested inside
  # `module Valuation`).

  TERMINAL_GROWTH = 0.03
  FORECAST_YEARS  = 5

  INDUSTRY_PE = {
    "Technology" => 35, "Communication Services" => 28,
    "Consumer Cyclical" => 20, "Consumer Defensive" => 22,
    "Healthcare" => 22, "Financial Services" => 15,
    "Industrials" => 20, "Basic Materials" => 14,
    "Energy" => 12, "Utilities" => 18,
    "Real Estate" => 18, "default" => 25
  }.freeze

  INDUSTRY_PB = {
    "Financial Services"    => 1.5, "Real Estate"        => 1.2,
    "Utilities"             => 1.8, "Technology"         => 8.0,
    "Healthcare"            => 4.0, "Consumer Cyclical"  => 1.2,
    "Industrials"           => 1.8, "Consumer Defensive" => 2.5,
    "Energy"                => 1.2, "Basic Materials"    => 1.5,
    "Communication Services" => 3.0, "default"           => 2.0
  }.freeze

  SECTOR_EV_EBITDA = {
    "Energy" => 8, "Basic Materials" => 10,
    "Industrials" => 14, "Consumer Cyclical" => 8,
    "default" => 12
  }.freeze

  INDUSTRY_PB_CYCLICAL = {
    "Consumer Cyclical" => 1.2, "Industrials" => 1.5,
    "default" => 1.0
  }.freeze

  CYCLICAL_KEYWORDS = %w[steel mining chemical oil gas copper coal automobile auto].freeze

  GROWTH_SECTORS          = [ "Technology", "Healthcare", "Communication Services" ].freeze
  GROWTH_CYCLICAL_SECTORS = [ "Energy", "Basic Materials", "Consumer Cyclical", "Industrials" ].freeze

  STOCK_TYPE_RATIONALE = {
    "一般股"   => "公司 EPS 為正且無特殊產業屬性，採主流三法估值：" \
                  "① DCF 現金流折現（核心內在價值，最全面）" \
                  "② P/E 本益比（市場最廣泛使用的相對估值）" \
                  "③ PEG 成長調整本益比（將成長速度納入定價，PEG=1 為公允）。",
    "金融股"   => "銀行保險業資本結構特殊，自由現金流難以直接衡量，採：" \
                  "① Excess Returns Model（ROE 超過 CoE 的超額報酬，是金融業最嚴謹的估值模型）" \
                  "② P/E 本益比（輔助參考）" \
                  "③ P/B 帳面價值倍數（金融業主流估值，反映資產品質）。",
    "REITs"    => "REITs 法定須分配 90% 以上盈餘，現金流穩定且可預測，採：" \
                  "① DDM 股利折現（最直接反映股東現金收益）" \
                  "② DCF（採較低成長率，強調穩定性）" \
                  "③ P/B（反映不動產資產評價）。",
    "公用事業" => "受政府管制、現金流極度穩定，但成長空間有限，採：" \
                  "① DDM 股利折現（穩定配息首選估值法）" \
                  "② DCF（以低折現率反映低風險特性）" \
                  "③ P/E（輔助確認市場定價合理性）。",
    "虧損成長股" => "公司 EPS 為負但具高成長潛力，傳統 P/E 失效，改採：" \
                    "① Rev×3 營收倍數（高成長公司市場慣用 P/S 定價，成長期以營收衡量規模）" \
                    "② DCF（保守估算，以較低成長上限進行現金流折現）。",
    "週期股"   => "週期性產業（能源/原材料/汽車/工業）盈餘受景氣循環大幅波動，" \
                  "不宜以當期 EPS 定價，採：" \
                  "① EV/EBITDA（企業整體價值對 EBITDA，排除財務槓桿與折舊差異，是週期股最穩健的估值）" \
                  "② P/B 帳面價值（資產型企業的底部支撐）" \
                  "③ DCF（以長期正常化現金流估算，避免週期高峰或低谷的失真）。"
  }.freeze

  METHOD_RATIONALE = {
    "DCF"       => "以企業未來自由現金流（FCF）逐年折現加總，反映最純粹的內在價值。" \
                   "輸入：FCF/股、預測期成長率 g、折現率 r（必要報酬率）、終端成長率 gt。",
    "P/E"       => "以產業平均本益比（P/E）乘以每股盈餘（EPS），反映市場對同類公司的定價水準。" \
                   "優點：直觀、廣泛使用；缺點：不納入成長性，高成長公司往往被低估。",
    "PEG"       => "在 P/E 基礎上調整成長率：PEG = P/E ÷ EPS成長率%。PEG = 1 視為公允價值，" \
                   "<1 代表相對便宜、>1 代表成長溢價。公允股價 = EPS × (成長率% × 1)。",
    "DDM"       => "戈登成長模型（Gordon Growth Model）：以下期股利 D₁ 除以（要求報酬率 r − 股利成長率 g）。" \
                   "適用穩定配息的成熟企業，直接衡量股東可領取的現金報酬。",
    "P/B"       => "以帳面每股淨值（BVPS）乘以產業平均 P/B 倍數，反映市場對資產品質的評價。" \
                   "適合資產密集型產業（金融、REITs、工業），P/B < 1 通常意味潛在低估。",
    "ExcessRet" => "超額報酬模型（Excess Returns Model）：公允價值 = 帳面淨值 + (ROE − 股東要求報酬率 CoE) × BVPS ÷ (CoE − g)。" \
                   "核心邏輯：若 ROE > CoE，公司正在為股東創造超額價值，應以溢價於帳面值交易。",
    "Rev×3"     => "以每股營收（Revenue/Share）乘以 3x P/S 倍數。適用於尚未獲利的高成長公司，" \
                   "市場以未來收入規模而非當期盈利定價。3x 為科技/生技成長股的參考中位數。",
    "EV/EBITDA" => "企業整體價值（EV = 市值 + 淨負債）÷ EBITDA。排除資本結構差異與折舊攤銷，" \
                   "是跨公司、跨週期比較最公允的指標。公允股價 = (EBITDA × 行業倍數 − 淨負債) ÷ 流通股數。"
  }.freeze

  # ── Main orchestrator ──────────────────────────────────────────
  class FairValue
    include Classifier
    include ValuationMethods

    def self.analyze(stock_data, discount_rate: 0.10)
      new(stock_data, discount_rate).analyze
    end

    def initialize(stock_data, discount_rate)
      @d = stock_data
      @r = discount_rate.clamp(0.06, 0.20)
    end

    def analyze
      stock_type  = classify
      growth_rate = estimate_growth_rate
      methods     = apply_methods(stock_type, growth_rate)
      values      = methods.map { |m| m[:value] }.compact

      {
        stock_type:           stock_type,
        stock_type_rationale: STOCK_TYPE_RATIONALE[stock_type],
        growth_rate:          growth_rate,
        growth_rate_note:     growth_rate_sources.join("、"),
        valuation_methods:    methods,
        fair_value_low:       values.min&.round(2),
        fair_value_high:      values.max&.round(2),
        judgment:             judge(@d[:current_price], values.min, values.max)
      }
    end

    private

    def apply_methods(stock_type, g)
      case stock_type
      when "一般股"     then [ dcf_method(g), pe_method, peg_method(g) ]
      when "金融股"     then [ excess_returns_method, pe_method, pb_method ]
      when "REITs"      then [ ddm_method(0.03), dcf_method(0.04), pb_method ]
      when "公用事業"   then [ ddm_method(0.025), dcf_method(0.04), pe_method ]
      when "虧損成長股" then [ rev_multiple_method, dcf_method([ g, 0.25 ].min) ]
      when "週期股"     then [ ev_ebitda_method, pb_method, dcf_method(g) ]
      else                   [ dcf_method(g), pe_method ]
      end.compact
    end

    def judge(price, lo, hi)
      return "⚪ 資料不足" if [ price, lo, hi ].any?(&:nil?)

      if    price > hi * 1.20 then "🔴 明顯高估"
      elsif price > hi        then "🟡 略微高估"
      elsif price < lo * 0.80 then "🟢 明顯低估（潛在買點）"
      elsif price < lo        then "🟡 略微低估"
      else                         "🟢 合理"
      end
    end
  end
end
