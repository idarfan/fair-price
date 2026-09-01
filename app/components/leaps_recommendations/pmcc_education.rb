# frozen_string_literal: true

module LeapsRecommendations::PmccEducation
  def render_pmcc_edu_section
    div(class: "pmcc-edu-root space-y-4") do
      render_pmcc_edu_golden_rule
      render_pmcc_edu_max_profit
      render_pmcc_edu_build_rules
      render_pmcc_edu_what_is_pmcc
    end
  end


  def pmcc_edu_pick
    return nil unless @pmcc_ranking && @pmcc_ranking[:status] == :ok

    all_combos = @pmcc_ranking[:summary][:expirations].flat_map { |k| @pmcc_ranking[k][:combos] }
    all_combos.find { |c| c[:passes_golden_rule] } || all_combos.first
  end


  def render_pmcc_edu_golden_rule
    pick = pmcc_edu_pick

    div(class: "bg-[#FFF7C0] border-[1.5px] border-[#E8B840] rounded-[10px] p-4") do
      div(class: "flex items-center gap-2 mb-2") do
        span(class: "text-lg") { plain "⚖" }
        h3(class: "text-sm font-semibold text-[#2A1A0E]") { plain "黃金法則（建倉前必驗算）" }
      end
      p(class: "text-sm font-mono text-[#D4900A] font-semibold mb-1") do
        plain "LEAPS買入成本 < Short Call履約價 − LEAPS履約價"
      end
      p(class: "text-xs text-[#7A6555] mb-1") { plain "差價=KS−KL 代表最多能賺多少（程式自動算，列於 Spread 欄）" }
      p(class: "text-xs text-red-600 font-semibold mb-2") { plain "費用超過差價即使方向對仍保證虧損" }

      if pick
        long_leg  = pick[:long_leg]
        short_leg = pick[:short_leg]
        p(class: "text-xs text-[#2A1A0E]") do
          if pick[:passes_golden_rule]
            plain "#{@symbol} $#{fmt_strike_short(long_leg[:strike])}→$#{fmt_strike_short(short_leg[:strike])} " \
                  "差價#{fmt_price(pick[:spread])} 費用#{fmt_price(long_leg[:mid])} → ✅"
          else
            plain "#{@symbol} $#{fmt_strike_short(long_leg[:strike])}→$#{fmt_strike_short(short_leg[:strike])} #{pick[:fail_reason]}"
          end
        end
      else
        p(class: "text-xs text-[#7A6555]") { plain "—" }
      end
    end
  end


  def render_pmcc_edu_max_profit
    pick = pmcc_edu_pick

    div(class: "bg-[#F0FAF0] border-[1.5px] border-[#8ED4A8] rounded-[10px] p-4") do
      div(class: "flex items-center gap-2 mb-2") do
        span(class: "text-lg") { plain "💰" }
        h3(class: "text-sm font-semibold text-[#2A1A0E]") { plain "最大獲利 = 差價 − 淨成本" }
      end
      p(class: "text-sm font-mono text-[#2E9E52] font-semibold mb-1") { plain "(KS−KL) − (PL−PS)" }
      p(class: "text-xs text-[#7A6555] mb-2") { plain "漲至 KS 以上時實現，列於 MaxProfit(含SC) 欄" }

      if pick
        long_leg  = pick[:long_leg]
        short_leg = pick[:short_leg]
        p(class: "text-xs text-[#2A1A0E]") do
          plain "本次範例：(#{fmt_price(short_leg[:strike])}−#{fmt_price(long_leg[:strike])}) − " \
                "(#{fmt_price(long_leg[:mid])}−#{fmt_price(short_leg[:mid])}) = #{fmt_price(pick[:max_profit])}"
        end
      else
        p(class: "text-xs text-[#7A6555]") { plain "—" }
      end
    end
  end


  def render_pmcc_edu_build_rules
    div(class: "bg-[#FEF4D8] border-2 border-[#E8B840] rounded-2xl p-4") do
      div(class: "flex items-center justify-between mb-3") do
        h3(class: "text-sm font-semibold text-[#2A1A0E]") { plain "📐 建倉規範" }
        span(class: "text-xs text-[#7A6555]") { plain "PMCC · 黃金法則" }
      end
      div(class: "grid grid-cols-2 gap-2 text-xs") do
        div(class: "text-[#3A70C0]") { plain "Long Delta ≥ 0.80" }
        div(class: "text-[#3A70C0]") { plain "Long DTE ≥ 180 天" }
        div(class: "text-[#D04040]") { plain "Short Delta 0.20–0.35" }
        div(class: "text-[#D04040]") { plain "Short DTE 19–45 天" }
      end
      p(class: "text-[11px] text-[#7A6555] mt-2") { plain "本表抓 DTE 60 天以內的到期日（最多 8 個），涵蓋上面的建議區間。" }
    end
  end


  def render_pmcc_edu_what_is_pmcc
    pick       = pmcc_edu_pick
    underlying = @candidates.first && @candidates.first[:underlying_price]

    div(class: "bg-[#FFFCF7] border-2 border-[#E2D4C2] rounded-2xl p-4") do
      div(class: "flex items-center gap-2 mb-2") do
        div(class: "w-6 h-6 rounded-full bg-black text-white flex items-center justify-center text-xs font-bold flex-shrink-0") { plain "1" }
        h3(class: "text-sm font-semibold text-[#2A1A0E]") { plain "WHAT IS PMCC" }
        span(class: "text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600") { plain "窮人版備兌買權" }
      end
      p(class: "text-sm font-semibold text-[#2A1A0E] mb-2") { plain "PMCC = LEAPS Long Call + Short Call" }

      div(class: "space-y-1.5 text-xs text-[#2A1A0E]") do
        if pick && underlying.present?
          long_leg        = pick[:long_leg]
          short_leg       = pick[:short_leg]
          cost_100_shares = underlying.to_f * 100
          leaps_cost      = long_leg[:mid].to_f * 100
          short_premium   = short_leg[:mid].to_f * 100
          capital_ratio   = cost_100_shares.zero? ? nil : (leaps_cost / cost_100_shares) * 100

          render_pmcc_bullet(1, "買100股成本 $#{fmt_int(cost_100_shares.round)}")
          render_pmcc_bullet(2, "LEAPS 成本 $#{fmt_int(leaps_cost.round)}")
          render_pmcc_bullet(3, "短期虛值 SC：60 天內到期日、Delta 0.20–0.35、收租 $#{fmt_int(short_premium.round)}")
          render_pmcc_bullet(4, "資金比例 #{capital_ratio ? fmt_pmcc_pct(capital_ratio) : '—'}")
        else
          render_pmcc_bullet(1, "買100股成本 —")
          render_pmcc_bullet(2, "LEAPS 成本 —")
          render_pmcc_bullet(3, "短期虛值 SC：60 天內到期日、Delta 0.20–0.35、收租 —")
          render_pmcc_bullet(4, "資金比例 —")
        end
      end
      p(class: "text-[10px] text-gray-400 mt-3") { plain "以上為策略框架說明，非投資建議，請自行評估。" }
    end
  end


  def render_pmcc_bullet(num, text)
    div(class: "flex items-start gap-2") do
      span(class: "flex-shrink-0 w-5 h-5 rounded-full border-2 border-[#D4900A] text-[#D4900A] " \
                   "text-[10px] font-bold flex items-center justify-center") { plain num.to_s }
      span { plain text }
    end
  end
end
