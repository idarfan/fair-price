# frozen_string_literal: true

class LeapsVerticalSpreadService
  # P6：8 格 tooltip 與賣出腳導覽的說明句（leaps-call-spread-spec「P6 說明」）。
  #
  # 所有數字都取自當下實際的買入腳、賣出腳與現價（LeapsVerticalSpreadService 的結果），
  # 不放任何固定範例；這裡只組句，不做計算（衍生值在 service 的 explanation_values）。
  # tooltip 的句子是純文字陣列（由 tooltips.js 轉義）；導覽的每一行是 [文字, 顏色] 片段，
  # 讓賺／平／賠的數字可以上色（由 leapsVerticalSpread.ts 轉義）。
  module Explanation
    TIP_KEYS = %i[long_leg short_leg net_cost max_profit breakeven max_loss risk_reward width].freeze
    FAR_FROM_TARGET = BigDecimal("0.05") # 預設賣出腳的 Δ 與 0.30 差超過這個值，就說明「找不到接近 0.30」

    module_function

    def tips(outcome)
      ctx = context(outcome)
      return {} unless ctx

      TIP_KEYS.index_with { |key| send(:"tip_#{key}", ctx) }
    end

    def tour(outcome)
      ctx = context(outcome)
      return [] unless ctx

      [ tour_role(ctx), tour_delta(ctx), tour_why(ctx), tour_max_profit(ctx),
        tour_breakeven(ctx), tour_early_exercise(ctx), tour_starting_point(ctx) ]
    end

    # ── 共用：把 outcome 攤成組句要用的字串 ──
    def context(outcome)
      result = outcome[:result]
      return nil unless result && outcome[:legs]

      long, short = outcome[:legs].values_at(:long, :short)
      display = result[:display]
      default = outcome.dig(:selected, :default_short_strike)
      {
        long: long, short: short, result: result, display: display, spot: outcome[:spot],
        k_l: Format.num(long[:strike]), k_s: Format.num(short[:strike]), date: long[:expiry][0, 10], dte: long[:dte],
        long_price: Format.num(long[:price]), short_price: Format.num(short[:price]),
        d_mid: Format.num(result[:d_mid]), spot_s: outcome[:spot] && Format.num(outcome[:spot]),
        default: default, default_option: default && outcome[:short_options]&.find { |o| o[:strike] == default },
        user_changed: default && default != short[:strike]
      }
    end

    def seg(text, tone = nil) = [ text, tone ]
    def line(*parts) = parts.map { |p| p.is_a?(Array) ? p : seg(p) }
    def price_word(leg) = leg[:source] == :last ? "最後成交價" : "買賣中價"
    def delta_s(leg) = leg[:delta] ? Format.num(leg[:delta]) : "—"

    # ── 8 格 tooltip ──
    def tip_long_leg(c)
      lines = [
        "你付錢買進的 LEAPS Call：到期日 #{c[:date]}（#{c[:dte]} 天），履約價 #{c[:k_l]}，" \
        "權利金 #{c[:long_price]}（#{price_word(c[:long])}），Δ #{delta_s(c[:long])}。",
        "履約價固定是你輸入的 #{c[:k_l]}，可以切換到期日：到期日越遠，時間越充裕，權利金通常越貴。",
        "預設選「LEAPS Call 候選排行」中履約價 #{c[:k_l]} 排名第一的到期日；沒有的話，選有報價的最遠到期日。"
      ]
      lines << "這一腳沒有買賣價，以最後成交價 #{c[:long_price]} 計算（盤後參考價），實際成交價可能不同。" if c[:long][:source] == :last
      { value: c[:long][:label], tone: nil, lines: lines }
    end

    def tip_short_leg(c)
      r = c[:result]
      lines = [
        "你同時賣出的 Call：同一個到期日 #{c[:date]}，履約價 #{c[:k_s]}" +
          (c[:spot_s] ? "，比現價 #{c[:spot_s]} 高 #{Format.pct(r[:short_vs_spot])}（價外）。" : "。"),
        "收到的權利金 #{c[:short_price]} 抵掉買入腳 #{c[:long_price]} 的 #{Format.pct(r[:premium_recovery], signed: false)}；" \
        "代價是股價漲過 #{c[:k_s]} 之後的獲利不屬於你。",
        default_sentence(c)
      ]
      if c[:short][:delta].nil? && r[:no_delta_target]
        lines << "這一檔沒有 Δ 資料；沒有 Δ 時，預設改選履約價最接近 現價 × 1.3（#{Format.num(r[:no_delta_target])}）的那一檔。"
      end
      lines << "這一腳沒有買賣價，以最後成交價 #{c[:short_price]} 計算（盤後參考價），實際成交價可能不同。" if c[:short][:source] == :last
      { value: c[:short][:label], tone: nil, lines: lines }
    end

    def default_sentence(c)
      return "系統預設選合格賣出腳中 Δ 最接近 0.30 的那一檔。" unless c[:default]
      return "這是系統預設：合格的賣出腳中 Δ 最接近 0.30 的那一檔（目前 Δ #{delta_s(c[:short])}）。" unless c[:user_changed]

      default_delta = c[:default_option] ? " Δ #{delta_s(c[:default_option])}" : ""
      "你改選了 #{c[:k_s]}；系統預設會選 Δ 最接近 0.30 的 #{Format.num(c[:default])}#{default_delta}。"
    end

    def tip_net_cost(c)
      r, disp = c[:result], c[:display]
      nat = if r[:d_nat]
        "小字「保守成交」用買入腳賣價 #{Format.num(c[:long][:ask])}、賣出腳買價 #{Format.num(c[:short][:bid])} 計算：" \
          "(#{Format.num(c[:long][:ask])} − #{Format.num(c[:short][:bid])}) × 100 = #{disp[:net_cost_nat]}，比較接近實際掛單成交的價格。"
      else
        "有一腳沒有買賣價（用盤後參考價），無法計算保守成交。"
      end
      { value: disp[:net_cost], tone: nil, lines: [
        "每口實際要付的錢 = (買入腳 #{c[:long_price]} − 賣出腳 #{c[:short_price]}) × 100 = #{c[:d_mid]} × 100 = #{disp[:net_cost]}（一口 100 股）。",
        nat
      ] }
    end

    def tip_max_profit(c)
      r, disp = c[:result], c[:display]
      lines = [ "到期時股價在賣出腳履約價 #{c[:k_s]} 以上，拿到最大獲利 = (價差寬度 #{disp[:width]} − 淨成本 #{c[:d_mid]}) × 100 = #{disp[:max_profit]}。" ]
      lines << "股價要從現價 #{c[:spot_s]} 漲到 #{c[:k_s]}，約 #{Format.pct(r[:short_vs_spot])}。" if c[:spot_s]
      lines << "要到到期日 #{c[:date]} 才完整實現；在那之前提早平倉，通常拿不到全部。"
      { value: disp[:max_profit], tone: :profit, lines: lines }
    end

    def tip_breakeven(c)
      r, disp = c[:result], c[:display]
      lines = [ "到期時股價要高於 買入腳履約價 #{c[:k_l]} + 每股淨成本 #{c[:d_mid]} = #{Format.num(r[:breakeven])} 才開始賺錢。" ]
      lines << breakeven_distance(c) if c[:spot_s]
      { value: disp[:breakeven], tone: :breakeven, lines: lines }
    end

    def breakeven_distance(c)
      gap = c[:result][:breakeven_vs_spot]
      return "目前現價 #{c[:spot_s]}，還要漲 #{Format.pct(gap)} 才到損益兩平。" if gap.positive?

      "目前現價 #{c[:spot_s]} 已經高於損益兩平（差 #{Format.pct(gap)}），只要到期時不跌破就不虧。"
    end

    def tip_max_loss(c)
      disp = c[:display]
      { value: disp[:max_loss], tone: :loss, lines: [
        "到期時股價在買入腳履約價 #{c[:k_l]} 以下，兩腳都沒有價值，付出的淨成本 #{disp[:net_cost]} 全部虧掉。",
        "這就是最多虧的金額，不會再多。"
      ] }
    end

    def tip_risk_reward(c)
      disp = c[:display]
      { value: disp[:risk_reward], tone: nil, lines: [
        "最多賺 #{disp[:max_profit]} ÷ 最多虧 #{disp[:max_loss]}，也就是 #{disp[:risk_reward]}。",
        "只比較兩個極端，沒有考慮發生的機率：要漲到 #{c[:k_s]} 以上才拿到最大獲利，跌破 #{c[:k_l]} 就是最大虧損。"
      ] }
    end

    def tip_width(c)
      disp = c[:display]
      { value: disp[:width], tone: nil, lines: [
        "賣出腳 #{c[:k_s]} − 買入腳 #{c[:k_l]} = #{disp[:width]}，是這個價差每股最多值多少錢。",
        "寬度越大，最大獲利的上限越高，但賣出腳收回的權利金越少，淨成本通常越高。"
      ] }
    end

    # ── 賣出腳導覽（7 步）──
    def step(anchor, title, lines) = { anchor: anchor, title: title, lines: lines }

    def tour_role(c)
      disp = c[:display]
      step(:short_leg, "賣出腳在做什麼", [
        line("垂直價差是「買一個低履約價的 Call，同時賣一個高履約價的 Call」。"),
        line("賣出腳收到的權利金 #{c[:short_price]} 直接抵掉買入腳的成本 #{c[:long_price]}；代價是股價漲過 #{c[:k_s]} 之後的獲利不屬於你。"),
        line("所以賣出腳決定三件事：要花多少錢（淨成本 #{disp[:net_cost]}）、最多賺多少（", seg(disp[:max_profit], :profit),
             "）、股價要漲到哪裡才開始賺（", seg(disp[:breakeven], :breakeven), "）。"),
        line(default_sentence(c))
      ])
    end

    def tour_delta(c)
      d = c[:short][:delta]
      lines = if d
        [ line("股價每漲 1 元，這張 #{c[:k_s]} 的 Call 大約漲 #{Format.num(d)} 元。"),
          line("Δ 也常被當成「到期時落在價內的機率」的粗略估計：Δ #{Format.num(d)} 大約代表市場認為，" \
               "到 #{c[:date]} 股價漲過 #{c[:k_s]} 的機會約 #{Format.pct(d, signed: false)}。") ]
      else
        [ line("這一檔沒有 Δ 資料。Δ 是股價每漲 1 元，Call 大約漲多少，也常被當成到期時落在價內的機率粗估。") ]
      end
      step(:short_leg, "Δ（Delta）是什麼", lines + [
        line("這是依市場目前的隱含波動率推算的近似值，會隨股價、時間、波動率一直變，也會稍微高估真正落在價內的機率；不是預測。")
      ])
    end

    def tour_why(c)
      r = c[:result]
      spot_part = c[:spot_s] ? "損益兩平距現價只有 #{Format.pct(r[:breakeven_vs_spot])}；" : ""
      step(:short_leg, "為什麼建議 Δ 0.30", [
        line("在三件事之間取平衡：收回買入腳 #{Format.pct(r[:premium_recovery], signed: false)} 的成本；#{spot_part}" \
             "還保留一段上漲空間（到 #{c[:k_s]}#{c[:spot_s] ? "，#{Format.pct(r[:short_vs_spot])}" : ''}）。"),
        line("賣得太近（Δ 高）：成本低、容易賺，但最多只能賺一點點，損益兩平甚至可能低於現價，等於花不少錢換很小的上限。"),
        line("賣得太遠（Δ 低）：收回的權利金很少，成本接近單買 LEAPS，要大漲才拿得到最大獲利。"),
        line("Δ 0.30 是選擇權交易常用的經驗法則，不是數學上的最佳解。")
      ])
    end

    def tour_max_profit(c)
      tip = tip_max_profit(c)
      step(:max_profit, "最大獲利", [ line("目前最大獲利 ", seg(tip[:value], :profit), "。") ] + tip[:lines].map { |t| line(t) })
    end

    def tour_breakeven(c)
      tip = tip_breakeven(c)
      step(:breakeven, "損益兩平", [ line("目前損益兩平 ", seg(tip[:value], :breakeven), "。") ] + tip[:lines].map { |t| line(t) })
    end

    def tour_early_exercise(c)
      r = c[:result]
      spot_part = c[:spot_s] ? "股價漲過 #{c[:k_s]}（從現價 #{c[:spot_s]} 要 #{Format.pct(r[:short_vs_spot])}）" : "股價漲過 #{c[:k_s]}"
      step(:short_leg, "提前履約與配息：LEAPS 價差為什麼很少遇到", [
        line("美股選擇權是美式的，買方可以在到期前任何一天履約；但提前履約會放棄剩下的時間價值，正常情況下買方寧可把選擇權賣掉。"),
        line("唯一的例外是配息：持有 Call 領不到股息，想領就得在除息日前一天履約換成股票；只有「每股股息 > 這張 Call 剩下的時間價值」時才划算。標的不配息就沒有提前履約的理由。"),
        line("你的賣出腳 #{c[:k_s]} 距離到期還有 #{c[:dte]} 天，目前時間價值 #{Format.num(r[:short_extrinsic])}（權利金 #{c[:short_price]}）；" \
             "一般一季的股息遠小於這麼長天期的時間價值，所以這個風險很少遇到。"),
        line("要讓條件成立，必須同時：#{spot_part}，而且時間價值消耗到比一次股息還少——實務上多半只在接近到期的最後一段時間。"),
        line("萬一在最後階段被指派：股價已在 #{c[:k_s]} 以上，本來就是拿最大獲利的狀態；履約手上的買入腳 #{c[:k_l]} 交出股票，結果約等於最大獲利 ",
             seg(c[:display][:max_profit], :profit), "；額外成本只有在除息日前被指派時，要替放空的 100 股付一次股息。"),
        line("你只需要做一件事：接近到期、而且賣出腳已在價內時留意除息日；時間價值比股息還小，就在除息日之前平倉或轉倉。本工具沒有抓股息資料，除息日請到券商或公司網站查詢。")
      ])
    end

    def tour_starting_point(c)
      lines = [
        line("更看漲、想要更高上限，就往 Δ 更低的檔選（履約價更高）；只想穩穩賺、預期漲幅不大，就往 Δ 更高的檔選（履約價更低）。")
      ]
      opt = c[:default_option]
      if opt && opt[:delta] && (opt[:delta] - LeapsVerticalSpreadService::TARGET_DELTA).abs > FAR_FROM_TARGET
        lines << line("這個到期日最接近 0.30 的是 #{Format.num(opt[:strike])}（Δ #{Format.num(opt[:delta])}），" \
                      "因為 chain 的履約價不夠高，找不到更接近的。")
      end
      lines << line("找不到剛好 0.30 時，系統選最接近的那一檔；資料沒有 Δ 時，改選履約價最接近 現價 × 1.3 的那一檔。")
      lines << line("以上只是計算與說明，不構成投資建議。")
      step(:short_leg, "0.30 是起點，不是答案", lines)
    end
  end
end
