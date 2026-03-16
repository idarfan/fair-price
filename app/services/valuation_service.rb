class ValuationService
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

  GROWTH_SECTORS         = %w[Technology Healthcare Communication\ Services].freeze
  GROWTH_CYCLICAL_SECTORS = %w[Energy Basic\ Materials Consumer\ Cyclical Industrials].freeze

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
      stock_type:          stock_type,
      stock_type_rationale: STOCK_TYPE_RATIONALE[stock_type],
      growth_rate:         growth_rate,
      growth_rate_note:    growth_rate_sources.join("、"),
      valuation_methods:   methods,
      fair_value_low:      values.min&.round(2),
      fair_value_high:     values.max&.round(2),
      judgment:            judge(@d[:current_price], values.min, values.max)
    }
  end

  private

  # ── Stock Classification ────────────────────────────────────

  def classify
    sector   = @d[:sector].to_s
    industry = @d[:industry].to_s.downcase
    eps      = @d[:eps_ttm]

    return "REITs"    if sector == "Real Estate"
    return "公用事業" if sector == "Utilities"
    return "金融股"   if sector == "Financial Services"

    if ["Energy", "Basic Materials"].include?(sector) ||
       CYCLICAL_KEYWORDS.any? { |k| industry.include?(k) }
      return "週期股"
    end

    # Consumer Cyclical / Industrials 虧損 → 週期性低谷，非成長股
    return "週期股" if GROWTH_CYCLICAL_SECTORS.include?(sector) && eps && eps < 0

    # 真正的虧損成長股：成長型產業 + 實質營收成長 > 10%
    if eps && eps < 0
      rev_growth = @d[:revenue_growth].to_f
      return "虧損成長股" if GROWTH_SECTORS.any? { |s| sector.include?(s) } && rev_growth > 0.10
      return "一般股"
    end

    "一般股"
  end

  # ── Growth Rate Estimation ──────────────────────────────────

  def growth_rate_sources
    @growth_rate_sources ||= begin
      sources = []
      sources << ["盈餘成長(YoY)", @d[:earnings_growth]]           if valid_growth?(@d[:earnings_growth])
      sources << ["營收成長",       @d[:revenue_growth]]            if valid_growth?(@d[:revenue_growth])
      sources << ["季度盈餘成長",   @d[:earnings_quarterly_growth]] if valid_growth?(@d[:earnings_quarterly_growth])

      if @d[:forward_eps] && @d[:eps_ttm]&.positive?
        fg = (@d[:forward_eps] - @d[:eps_ttm]) / @d[:eps_ttm]
        sources << ["FwdEPS推算", fg] if valid_growth?(fg)
      end

      sources
    end
  end

  def estimate_growth_rate
    sources = growth_rate_sources.map(&:last)
    return 0.10 if sources.empty?

    sorted = sources.sort
    sorted[sorted.length / 2].clamp(0.03, 0.45)
  end

  def valid_growth?(v)
    v&.between?(-0.5, 2.0)
  end

  # ── Method Selection by Stock Type ─────────────────────────

  def apply_methods(stock_type, g)
    case stock_type
    when "一般股"     then [dcf_method(g), pe_method, peg_method(g)]
    when "金融股"     then [excess_returns_method, pe_method, pb_method]
    when "REITs"      then [ddm_method(0.03), dcf_method(0.04), pb_method]
    when "公用事業"   then [ddm_method(0.025), dcf_method(0.04), pe_method]
    when "虧損成長股" then [rev_multiple_method, dcf_method([g, 0.25].min)]
    when "週期股"     then [ev_ebitda_method, pb_method, dcf_method(g)]
    else                   [dcf_method(g), pe_method]
    end.compact
  end

  # ── Valuation Methods ───────────────────────────────────────

  def dcf_method(g, label: "DCF")
    fcf_ps = per_share(@d[:free_cashflow], @d[:shares_outstanding])
    fcf_ps = adjust_fcf(fcf_ps)
    return nil unless fcf_ps&.positive?

    value = dcf(fcf_ps, g)
    return nil unless value&.positive?

    {
      method:    label,
      value:     value.round(2),
      note:      "FCF r=#{pct(@r)} g=#{pct(g)}",
      formula:   "FCF/股=$#{fcf_ps.round(2)} → 預測#{FORECAST_YEARS}年(g=#{pct(g)}) + 終端價值(gt=#{pct(TERMINAL_GROWTH)}) → 折現(r=#{pct(@r)})",
      rationale: METHOD_RATIONALE["DCF"]
    }
  end

  def pe_method
    eps    = @d[:eps_ttm]
    sector = @d[:sector].to_s
    return nil unless eps&.positive?

    pe    = INDUSTRY_PE[sector] || INDUSTRY_PE["default"]
    value = eps * pe
    {
      method:    "P/E",
      value:     value.round(2),
      note:      "EPS $#{eps.round(2)} × #{pe}x",
      formula:   "Trailing EPS $#{eps.round(2)} × #{sector.presence || '產業'}平均 P/E #{pe}x = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["P/E"]
    }
  end

  def peg_method(g)
    eps   = (@d[:forward_eps] || @d[:eps_ttm])
    price = @d[:current_price]
    return nil unless eps&.positive? && g&.positive?

    g_pct    = g * 100
    value    = eps * g_pct
    cur_pe   = (price && price > 0) ? price / eps : nil
    cur_peg  = cur_pe ? (cur_pe / g_pct).round(2) : nil

    {
      method:    "PEG",
      value:     value.round(2),
      note:      "PEG=1 公允價（當前PEG=#{cur_peg || 'N/A'}）",
      formula:   "公式：P/E ÷ g% → PEG=1時 公允P/E=#{g_pct.round(0)}x → $#{eps.round(2)} × #{g_pct.round(0)} = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["PEG"]
    }
  end

  def ddm_method(g, required_return: 0.08)
    div = @d[:dividend_rate]
    return nil unless div&.positive? && required_return > g

    value = div * (1 + g) / (required_return - g)
    {
      method:    "DDM",
      value:     value.round(2),
      note:      "配息 $#{div.round(3)}",
      formula:   "D₁ = $#{div.round(3)}×(1+#{pct(g)}) ÷ (r=#{pct(required_return)} − g=#{pct(g)}) = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["DDM"]
    }
  end

  def pb_method
    bvps   = @d[:book_value]
    sector = @d[:sector].to_s
    return nil unless bvps&.positive?

    pb    = INDUSTRY_PB[sector] || INDUSTRY_PB["default"]
    value = bvps * pb
    {
      method:    "P/B",
      value:     value.round(2),
      note:      "BVPS $#{bvps.round(2)} × #{pb}x",
      formula:   "每股淨值 $#{bvps.round(2)} × #{sector.presence || '產業'}平均 P/B #{pb}x = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["P/B"]
    }
  end

  def excess_returns_method
    bvps = @d[:book_value]
    roe  = @d[:roe]
    coe  = 0.10
    g    = 0.03
    return nil unless bvps&.positive? && roe && coe > g

    value = bvps + (roe - coe) * bvps / (coe - g)
    return nil unless value&.positive?

    {
      method:    "ExcessRet",
      value:     value.round(2),
      note:      "ROE #{(roe * 100).round(1)}%",
      formula:   "BV $#{bvps.round(2)} + (ROE #{(roe * 100).round(1)}% − CoE #{pct(coe)}) × BV ÷ (CoE−g) = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["ExcessRet"]
    }
  end

  def rev_multiple_method
    rev_ps = per_share(@d[:total_revenue], @d[:shares_outstanding])
    return nil unless rev_ps&.positive?

    # Rev×3 只適用於高成長型產業（SaaS/biotech/新創）
    # 傳統產業 P/S 遠低於 1x，不應套用此倍數
    sector = @d[:sector].to_s
    return nil unless GROWTH_SECTORS.any? { |s| sector.include?(s) }

    value = rev_ps * 3
    {
      method:    "Rev×3",
      value:     value.round(2),
      note:      "Rev/Share × 3x 營收倍數",
      formula:   "每股營收 $#{rev_ps.round(2)} × 3x = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["Rev×3"]
    }
  end

  def ev_ebitda_method
    ebitda  = @d[:ebitda]
    shares  = @d[:shares_outstanding]
    sector  = @d[:sector].to_s
    return nil unless ebitda&.positive? && shares&.positive?

    net_debt = (@d[:total_debt] || 0) - (@d[:total_cash] || 0)
    mult     = SECTOR_EV_EBITDA[sector] || SECTOR_EV_EBITDA["default"]
    equity   = ebitda * mult - net_debt
    return nil unless equity > 0

    value = equity / shares
    {
      method:    "EV/EBITDA",
      value:     value.round(2),
      note:      "× #{mult}x",
      formula:   "EBITDA × #{mult}x(#{sector.presence || '產業'}) − 淨負債 ÷ 流通股數 = $#{value.round(2)}",
      rationale: METHOD_RATIONALE["EV/EBITDA"]
    }
  end

  # ── Judgment ────────────────────────────────────────────────

  def judge(price, lo, hi)
    return "⚪ 資料不足" if [price, lo, hi].any?(&:nil?)

    if    price > hi * 1.20 then "🔴 明顯高估"
    elsif price > hi        then "🟡 略微高估"
    elsif price < lo * 0.80 then "🟢 明顯低估（潛在買點）"
    elsif price < lo        then "🟡 略微低估"
    else                         "🟢 合理"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  def dcf(fcf, g)
    return nil unless fcf&.positive?

    cf = fcf.to_f
    pv = (1..FORECAST_YEARS).sum do |n|
      cf *= (1 + g)
      cf / (1 + @r)**n
    end

    terminal = cf * (1 + TERMINAL_GROWTH) /
               ((@r - TERMINAL_GROWTH) * (1 + @r)**FORECAST_YEARS)
    pv + terminal
  end

  def per_share(total, shares)
    return nil unless total && shares&.positive?

    total.to_f / shares.to_f
  end

  def adjust_fcf(fcf_ps)
    eps = @d[:eps_ttm]
    return fcf_ps unless fcf_ps && eps&.positive?

    ratio = fcf_ps / eps
    return eps * 0.75 if ratio < 0.30
    return fcf_ps     if ratio <= 3.0

    fcf_ps
  end

  def pct(n)
    "#{(n * 100).round(1)}%"
  end
end
