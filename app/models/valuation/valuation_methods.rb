# frozen_string_literal: true

module Valuation
  # All individual valuation method implementations.
  # Each method returns a hash with :method, :value, :note, :formula, :rationale.
  # Returns nil when required inputs are unavailable.
  module ValuationMethods
    private

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

      g_pct   = g * 100
      value   = eps * g_pct
      cur_pe  = (price && price > 0) ? price / eps : nil
      cur_peg = cur_pe ? (cur_pe / g_pct).round(2) : nil

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
      ebitda = @d[:ebitda]
      shares = @d[:shares_outstanding]
      sector = @d[:sector].to_s
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

    # ── Calculation Helpers ─────────────────────────────────────

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
end
