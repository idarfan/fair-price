# frozen_string_literal: true

module LeapsRecommendations::ConceptCards
  include LeapsRecommendations::SharedConstants

  def render_recommendation
    near = @recommendation[:near_term]
    far  = @recommendation[:far_term]

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50") do
        h2(class: "text-sm font-semibold text-gray-700") { plain "推薦分析 — #{@symbol}" }
        p(class: "text-xs text-gray-400 mt-0.5") { plain "近天期 DTE 364–550 / 遠天期 DTE 550+，各自依流動性獨立挑選" }
      end
      div(class: "divide-y divide-gray-100") do
        render_recommendation_group(near)
        render_recommendation_group(far)
      end
      render_concept_cards
    end
  end


  # ── 第一部分：推薦分析名詞解釋圖卡（leaps-column-tooltips-spec.md 第一部分）────
  # 數值來源合約：遠天期推薦優先、無則近天期；完全無推薦不渲染。
  # 原生 details/summary 零 JS；深色卡面；匯出要入鏡（不加 data-export-exclude）。
  def concept_pick
    far  = @recommendation&.dig(:far_term)
    near = @recommendation&.dig(:near_term)
    [ far, near ].compact.find { |g| !g[:no_candidates] && g[:pick] }&.dig(:pick)
  end


  def render_concept_cards
    pick = concept_pick
    return unless pick

    div(class: "px-4 py-3 border-t border-gray-100 bg-gray-50 space-y-2") do
      p(class: "text-xs text-gray-400") do
        plain "名詞解釋（以本次推薦 $#{fmt_strike_short(pick[:strike])} / #{pick[:expiration_date]} 的實際數值試算）"
      end
      render_oi_card(pick)
      render_delta_card(pick)
      render_spread_card(pick)
      render_time_value_card(pick)
      render_iv_card(pick)
      render_vega_card(pick)
      render_iv_crush_card(pick)
    end
  end


  def concept_card(title, &block)
    details(class: "leaps-concept-card") do
      summary(class: "leaps-concept-summary") { plain title }
      div(class: "leaps-concept-body", &block)
    end
  end


  def render_oi_card(pick)
    oi     = pick[:open_interest]
    tier   = pick[:liquidity_tier].to_s
    warned = pick[:no_recent_volume_warning]
    concept_card("🔓 Open Interest（未平倉量）") do
      p do
        plain "市場上還沒被平倉的合約總數，只在盤後更新一次（跟即時成交量 Volume 不同）。是本表排行的排序主鍵。"
      end
      p do
        plain "本合約 OI #{fmt_int(oi)}，本次查詢候選中的相對排名為"
        strong { plain "「#{tier}」" }
        plain "。OI 越高，通常代表這個履約價／到期日組合有越多人在交易，掛單簿越厚、進出價格越不容易被自己的單子打歪。"
      end
      if warned
        p do
          strong { plain "⚠ 但本合約近期無成交" }
          plain "（Volume 對 OI 比率偏低）——OI 高不代表現在還在動，掛單簿可能已經很久沒更新，實際進出前務必先看報價是否合理、掛限價單試單。"
        end
      else
        p { plain "OI 高只代表「歷史上累積的未平倉量」，不保證今天一定買得到／賣得掉，仍要搭配 Volume 一起看。" }
      end
    end
  end


  def render_delta_card(pick)
    delta = pick[:delta].to_f
    dte   = pick[:dte].to_i
    concept_card("⚡ Delta（方向敏感度）") do
      p do
        plain "股價每漲 $1，這口合約的權利金理論上會變動多少錢；也常被拿來當「到期價內機率」的粗略估計。"
      end
      p do
        plain "本合約 Delta #{sprintf('%.3f', delta)}，代表股價 +$1 時，權利金理論上約 +$#{sprintf('%.2f', delta)}；"
        strong { plain "越接近 1，行為越像直接持有正股" }
        plain "（100 股），但用的資金遠比買正股少，這正是深價內 LEAPS 被拿來取代持股的原因。"
      end
      p do
        plain "本表只挑 Delta ≥ 0.60 的深價內合約：太低（Delta 太小）槓桿雖高但方向不夠貼近正股、時間價值佔比也高；Delta 越接近 1 則越像股票替代品，買進成本已經很接近正股，槓桿效益變小，但仍會列出讓你自行判斷。DTE #{dte} 天——天期越長，同一履約價的 Delta 通常越往中間值靠攏（時間價值稀釋方向性），這也是「深價內＋長天期」要挑履約價再往下修正緩衝的原因。"
      end
    end
  end


  def render_time_value_card(pick)
    tv_pct = pick[:time_value_pct]
    extrinsic = pick[:extrinsic_value]&.to_f
    spot      = pick[:underlying_price].to_f
    concept_card("📐 Time Value%（時間價值溢價）") do
      p do
        plain "外在價值除以"
        strong { plain "股價" }
        plain "（不是除以權利金 Mid，這是它跟「外在佔比」卡的關鍵差異）——回答的問題是「跟直接持有正股比，我用這口合約多付了幾 % 的溢價」。"
      end
      if tv_pct && extrinsic
        p do
          plain "本合約外在價值 $#{sprintf('%.2f', extrinsic)}、現價 $#{sprintf('%.2f', spot)}，Time Value 溢價約 "
          strong { plain "#{fmt_pct(tv_pct)}" }
          plain "——換句話說，用這口 LEAPS 取代持有 100 股正股，多付出的成本大約是股價的這個百分比，是你為了少壓資金、卻仍保留大部分漲幅所付出的代價。"
        end
      else
        p { plain "本合約缺少 bid/ask 或現價資料，Time Value% 無法計算，顯示為「—」。" }
      end
      p { plain "Time Value% 越低，代表這口合約的溢價成本越接近直接持股；搭配「外在佔比」卡一起看：兩者分母不同（一個除股價、一個除權利金），回答的是「多付幾 % 股價」跟「權利金裡幾 % 是保險費」兩個不同問題，不要混為一談。" }
    end
  end


  def render_spread_card(pick)
    bid = pick[:bid].to_f; ask = pick[:ask].to_f; mid = pick[:mid].to_f
    d   = ask - bid
    concept_card("📉 Bid-Ask Spread（買賣價差）") do
      p do
        plain "買方掛單的天花板（Ask）與底價（Bid）的距離，是"
        strong { plain "進出場的隱形成本" }
        plain "。"
      end
      p do
        plain "以本次推薦為例：Spread $#{sprintf('%.2f', d)}（#{fmt_pct(pick[:bid_ask_spread_pct])}）——用市價單買進再賣出，一來一回直接損失約 "
        strong { plain "$#{fmt_int(d * 100)}/口" }
        plain "，還沒算股價變動。"
      end
      p do
        plain "LEAPS 深價內檔位成交稀疏，Spread 普遍偏寬；"
        strong { plain "務必用限價單掛 Mid（$#{sprintf('%.2f', mid)}）附近" }
        plain "，可省下約一半的滑價成本。Spread% 超過 10% 的合約，進出場成本已足以吃掉數個百分點的獲利，部位規劃要把這筆成本算進去。"
      end
    end
  end


  def render_iv_card(pick)
    iv_pct  = pick[:iv].to_f * 100
    monthly = iv_pct / Math.sqrt(12)
    concept_card("🌊 IV（隱含波動率）") do
      p do
        plain "市場從權利金反推出的"
        strong { plain "預期年化波動率" }
        plain "。本合約 IV #{sprintf('%.1f', iv_pct)}%，代表市場預期未來一年股價年化波動約 ±#{sprintf('%.1f', iv_pct)}%（換算每月約 ±#{sprintf('%.1f', monthly)}%）。"
      end
      p do
        plain "對買方的意義："
        strong { plain "IV 越高，你買的權利金越貴" }
        plain "——外在價值裡的波動率溢價成分越大。在高 IV 時買進 LEAPS，等於用貴的價格買保險；就算方向看對，IV 回落也會侵蝕獲利（詳見 IV Crush 卡）。"
      end
    end
  end


  def render_vega_card(pick)
    vega = pick[:vega].to_f
    concept_card("🌀 Vega（IV 敏感度）") do
      p do
        plain "IV 每變動 1%，權利金的理論變化量。本合約 Vega #{sprintf('%.4f', vega)}，即 "
        strong { plain "IV 每降 1%，每口損失約 $#{sprintf('%.2f', vega * 100)}" }
        plain "。"
      end
      p do
        plain "天期越長 Vega 越大——這正是 LEAPS 的特性：DTE #{pick[:dte].to_i} 天給了 IV 均值回歸充分的時間，Vega 曝險遠高於短天期合約。壓低 Vega 風險的方法是選更深價內（外在佔比更低）的履約價。"
      end
    end
  end


  # IV Crush 試算的唯一計算處：HTML 卡片與 PDF 都呼叫這個方法，防呆分支
  # （iv<=90% 時改用「回落 10 個百分點」）只寫一次，避免兩邊各自判斷產生漂移。
  def iv_crush_calc(pick)
    iv_pct = pick[:iv].to_f * 100
    vega   = pick[:vega].to_f
    mid    = pick[:mid].to_f
    spot   = pick[:underlying_price].to_f
    if iv_pct > 90
      drop_desc = "若回落至 90%（對高波動股仍屬偏高水位）"
      drop_pts  = iv_pct - 90
      formula   = "(#{sprintf('%.1f', iv_pct)}−90) × Vega #{sprintf('%.4f', vega)}"
    else
      drop_desc = "若回落 10 個百分點"
      drop_pts  = 10.0
      formula   = "10 × Vega #{sprintf('%.4f', vega)}"
    end
    loss = drop_pts * vega
    {
      iv_pct: iv_pct, vega: vega, mid: mid, spot: spot,
      drop_desc: drop_desc, formula: formula, loss: loss,
      earnings: @next_earnings.present? ? @next_earnings.to_s : "暫無財報日資料"
    }
  end


  def render_iv_crush_card(pick)
    v = iv_crush_calc(pick)
    iv_pct, vega, mid, spot = v[:iv_pct], v[:vega], v[:mid], v[:spot]
    drop_desc, formula, loss, earnings = v[:drop_desc], v[:formula], v[:loss], v[:earnings]

    concept_card("⚡ IV Crush 風險（波動率回落損失）") do
      p do
        plain "高 IV 不會永遠維持——財報公布、事件落地、恐慌消退後，IV 常快速回落，權利金中的波動率溢價瞬間蒸發，這就是 IV Crush。"
        strong { plain "股價沒跌，你的合約照樣虧損。" }
      end
      p do
        plain "用本合約試算：IV #{sprintf('%.1f', iv_pct)}% #{drop_desc}，損失 ≈ #{formula} ≈ "
        strong { plain "$#{sprintf('%.2f', loss)}/股（每口 $#{fmt_int(loss * 100)}）" }
        if mid.positive? && spot.positive?
          plain "，約佔權利金 #{sprintf('%.1f', loss / mid * 100)}%——等於股價要先漲 #{sprintf('%.1f', loss / spot * 100)}% 才能打平這筆隱形損耗。"
        else
          plain "。"
        end
      end
      p do
        plain "防禦方式：(1) 選外在佔比低的深價內履約價（本卡損失全部發生在外在價值上，內在價值不受 IV 影響）；(2) 避開財報前 IV 高峰進場（下次財報：#{earnings}）；(3) 用 IV Rank 判斷目前 IV 處於歷史高位或低位。"
      end
    end
  end


  def render_recommendation_group(group)
    div(class: "px-4 py-4") do
      h3(class: "text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2") { plain group[:label] }
      if group[:no_candidates]
        div(class: "text-sm text-gray-400 italic") { plain "此天期區間目前沒有符合條件的候選。" }
      else
        pick = group[:pick]
        expired_s = partial_error_strike
        pick_incomplete = expired_s && pick[:strike].to_f == expired_s
        div(class: "flex flex-wrap gap-3 mb-3") do
          render_pick_badge(pick)
          if pick_incomplete
            span(class: "text-xs text-orange-600 self-center font-medium") { plain "⚠️ 此推薦的 Vega/被指派機率資料可能不完整" }
          end
          if (ru = group[:runner_up])
            div(class: "text-xs text-gray-400 self-center") { plain "次選：#{sprintf('$%.2f', ru[:strike].to_f)} / #{ru[:expiration_date]}" }
          end
        end
        div(class: "text-sm text-gray-700 whitespace-pre-line leading-relaxed") { plain group[:reason] }
      end
    end
  end


  def render_pick_badge(pick)
    tier  = pick[:liquidity_tier].to_s
    style = LIQUIDITY_STYLE[tier] || LIQUIDITY_STYLE["普通"]
    div(class: "flex items-center gap-2 px-3 py-1.5 rounded-lg border #{style[:bg]} #{style[:border]}") do
      div(class: "w-2 h-2 rounded-full #{style[:dot]}")
      span(class: "text-xs font-semibold #{style[:text]}") do
        plain "#{sprintf('$%.2f', pick[:strike].to_f)} / #{pick[:expiration_date]}"
      end
      span(class: "text-xs #{style[:text]} opacity-70") { plain "Delta #{sprintf("%.3f", pick[:delta].to_f)}" }
    end
  end
end
