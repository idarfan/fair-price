# frozen_string_literal: true

module LeapsRecommendations::PdfExport
  include LeapsRecommendations::SharedConstants

  # Phase J（leaps-phase-j-vector-pdf-spec.md）：向量 PDF 用的結構化資料 payload。
  # 用既有 fmt_* helper 格式化，確保 PDF 顯示的數字格式與頁面 HTML 完全一致，
  # 不在 JS 端另寫一套格式化邏輯（避免兩處數字格式漂移）。
  def pdf_export_payload
    pick      = concept_pick
    flow_ok   = @flow_panel&.dig(:status) == :ok
    {
      symbol: @symbol.to_s,
      recommendation: @recommendation ? {
        near_term: pdf_reco_group(@recommendation[:near_term]),
        far_term:  pdf_reco_group(@recommendation[:far_term])
      } : nil,
      candidates: @candidates.map { |row| pdf_candidate_row(row) },
      # 欄位順序（admin 可拖曳調整）也要進 PDF，否則畫面與匯出檔會對不起來。
      # 「價格預估」是試算按鈕，平面文件上沒有意義，不列入。
      column_order: ordered_col_keys - LeapsTableColumns::PDF_EXCLUDED_KEYS,
      column_labels: LeapsTableColumns::LABELS,
      # Options Flow 面板的完整內容，不只前 20 大成交列表：標題列的日期／Call
      # 、Put 總額，以及「排行候選 × 今日 Flow 重疊」提示，這三塊先前只有列表
      # 進了 PDF，總額與重疊提示遺漏（使用者實測發現），這裡一次補齊。
      flow_summary: flow_ok ? {
        date:       @flow_panel[:date].to_s,
        call_total: fmt_premium(@flow_panel[:call_premium_total]),
        put_total:  fmt_premium(@flow_panel[:put_premium_total]),
        call_color: "#16a34a", # text-green-600（跟 HTML render_flow_panel 同一個 class）
        put_color:  "#ef4444"  # text-red-500
      } : nil,
      flow_highlights: flow_ok ? Array(@flow_panel[:highlighted_trades]).map { |hit|
        "排行 ##{hit[:rank]} · $#{sprintf('%.2f', hit[:candidate_strike].to_f)} / #{hit[:candidate_expiry]} — #{hit[:trades].size} 筆匹配"
      } : [],
      flow_rows: (flow_ok ? Array(@flow_panel[:large_orders]).map { |t| pdf_flow_row(t) } : []),
      concept_cards: pick ? pdf_concept_cards_data(pick) : [],
      # 術語字卡（VOCAB_CARDS 15 張）：PDF 是平面文件沒有翻面概念，正反面
      # 攤平合併顯示（英文/音標/中文/提示 + 解釋/例句），不留白等待翻面。
      vocab_cards: VOCAB_CARDS.map { |card|
        { en: card[:en], ipa: card[:ipa], zh: card[:zh], hint: card[:hint], back: card[:back], ex: card[:ex] }
      }
    }
  end


  # 名詞解釋圖卡的 PDF 純文字版：同一份 pick 與同一批 fmt_* helper／iv_crush_calc
  # 計算值，只是把 HTML 的 strong/plain 混排文字合併成單一段落字串（PDF 向量繪製
  # 目前只嵌入 Regular 字重，不支援粗體切換，純文字讀起來仍完整不影響理解）。
  def pdf_concept_cards_data(pick)
    oi     = pick[:open_interest]
    tier   = pick[:liquidity_tier].to_s
    warned = pick[:no_recent_volume_warning]
    delta  = pick[:delta].to_f
    dte    = pick[:dte].to_i
    bid = pick[:bid].to_f; ask = pick[:ask].to_f; mid = pick[:mid].to_f
    spread_diff = ask - bid
    tv_pct = pick[:time_value_pct]
    extrinsic = pick[:extrinsic_value]&.to_f
    spot = pick[:underlying_price].to_f
    iv_pct = pick[:iv].to_f * 100
    monthly = iv_pct / Math.sqrt(12)
    vega = pick[:vega].to_f
    crush = iv_crush_calc(pick)

    [
      { title: "🔓 Open Interest（未平倉量）", paragraphs: [
        "市場上還沒被平倉的合約總數，只在盤後更新一次（跟即時成交量 Volume 不同）。是本表排行的排序主鍵。",
        "本合約 OI #{fmt_int(oi)}，本次查詢候選中的相對排名為「#{tier}」。OI 越高，通常代表這個履約價／到期日組合有越多人在交易，掛單簿越厚、進出價格越不容易被自己的單子打歪。",
        warned ?
          "⚠ 但本合約近期無成交（Volume 對 OI 比率偏低）——OI 高不代表現在還在動，掛單簿可能已經很久沒更新，實際進出前務必先看報價是否合理、掛限價單試單。" :
          "OI 高只代表「歷史上累積的未平倉量」，不保證今天一定買得到／賣得掉，仍要搭配 Volume 一起看。"
      ] },
      { title: "⚡ Delta（方向敏感度）", paragraphs: [
        "股價每漲 $1，這口合約的權利金理論上會變動多少錢；也常被拿來當「到期價內機率」的粗略估計。",
        "本合約 Delta #{sprintf('%.3f', delta)}，代表股價 +$1 時，權利金理論上約 +$#{sprintf('%.2f', delta)}；越接近 1，行為越像直接持有正股（100 股），但用的資金遠比買正股少，這正是深價內 LEAPS 被拿來取代持股的原因。",
        "本表只挑 Delta ≥ 0.60 的深價內合約：太低（Delta 太小）槓桿雖高但方向不夠貼近正股、時間價值佔比也高；Delta 越接近 1 則越像股票替代品，買進成本已經很接近正股，槓桿效益變小，但仍會列出讓你自行判斷。DTE #{dte} 天——天期越長，同一履約價的 Delta 通常越往中間值靠攏（時間價值稀釋方向性），這也是「深價內＋長天期」要挑履約價再往下修正緩衝的原因。"
      ] },
      { title: "📉 Bid-Ask Spread（買賣價差）", paragraphs: [
        "買方掛單的天花板（Ask）與底價（Bid）的距離，是進出場的隱形成本。",
        "以本次推薦為例：Spread $#{sprintf('%.2f', spread_diff)}（#{fmt_pct(pick[:bid_ask_spread_pct])}）——用市價單買進再賣出，一來一回直接損失約 $#{fmt_int(spread_diff * 100)}/口，還沒算股價變動。",
        "LEAPS 深價內檔位成交稀疏，Spread 普遍偏寬；務必用限價單掛 Mid（$#{sprintf('%.2f', mid)}）附近，可省下約一半的滑價成本。Spread% 超過 10% 的合約，進出場成本已足以吃掉數個百分點的獲利，部位規劃要把這筆成本算進去。"
      ] },
      { title: "📐 Time Value%（時間價值溢價）", paragraphs: [
        "外在價值除以股價（不是除以權利金 Mid，這是它跟「外在佔比」卡的關鍵差異）——回答的問題是「跟直接持有正股比，我用這口合約多付了幾 % 的溢價」。",
        (tv_pct && extrinsic) ?
          "本合約外在價值 $#{sprintf('%.2f', extrinsic)}、現價 $#{sprintf('%.2f', spot)}，Time Value 溢價約 #{fmt_pct(tv_pct)}——換句話說，用這口 LEAPS 取代持有 100 股正股，多付出的成本大約是股價的這個百分比，是你為了少壓資金、卻仍保留大部分漲幅所付出的代價。" :
          "本合約缺少 bid/ask 或現價資料，Time Value% 無法計算，顯示為「—」。",
        "Time Value% 越低，代表這口合約的溢價成本越接近直接持股；搭配「外在佔比」卡一起看：兩者分母不同（一個除股價、一個除權利金），回答的是「多付幾 % 股價」跟「權利金裡幾 % 是保險費」兩個不同問題，不要混為一談。"
      ] },
      { title: "🌊 IV（隱含波動率）", paragraphs: [
        "市場從權利金反推出的預期年化波動率。本合約 IV #{sprintf('%.1f', iv_pct)}%，代表市場預期未來一年股價年化波動約 ±#{sprintf('%.1f', iv_pct)}%（換算每月約 ±#{sprintf('%.1f', monthly)}%）。",
        "對買方的意義：IV 越高，你買的權利金越貴——外在價值裡的波動率溢價成分越大。在高 IV 時買進 LEAPS，等於用貴的價格買保險；就算方向看對，IV 回落也會侵蝕獲利（詳見 IV Crush 卡）。"
      ] },
      { title: "🌀 Vega（IV 敏感度）", paragraphs: [
        "IV 每變動 1%，權利金的理論變化量。本合約 Vega #{sprintf('%.4f', vega)}，即 IV 每降 1%，每口損失約 $#{sprintf('%.2f', vega * 100)}。",
        "天期越長 Vega 越大——這正是 LEAPS 的特性：DTE #{dte} 天給了 IV 均值回歸充分的時間，Vega 曝險遠高於短天期合約。壓低 Vega 風險的方法是選更深價內（外在佔比更低）的履約價。"
      ] },
      { title: "⚡ IV Crush 風險（波動率回落損失）", paragraphs: [
        "高 IV 不會永遠維持——財報公布、事件落地、恐慌消退後，IV 常快速回落，權利金中的波動率溢價瞬間蒸發，這就是 IV Crush。股價沒跌，你的合約照樣虧損。",
        "用本合約試算：IV #{sprintf('%.1f', crush[:iv_pct])}% #{crush[:drop_desc]}，損失 ≈ #{crush[:formula]} ≈ $#{sprintf('%.2f', crush[:loss])}/股（每口 $#{fmt_int(crush[:loss] * 100)}）" +
          ((crush[:mid].positive? && crush[:spot].positive?) ?
            "，約佔權利金 #{sprintf('%.1f', crush[:loss] / crush[:mid] * 100)}%——等於股價要先漲 #{sprintf('%.1f', crush[:loss] / crush[:spot] * 100)}% 才能打平這筆隱形損耗。" :
            "。"),
        "防禦方式：(1) 選外在佔比低的深價內履約價（本卡損失全部發生在外在價值上，內在價值不受 IV 影響）；(2) 避開財報前 IV 高峰進場（下次財報：#{crush[:earnings]}）；(3) 用 IV Rank 判斷目前 IV 處於歷史高位或低位。"
      ] }
    ]
  end


  def pdf_reco_group(group)
    return nil unless group
    pick = group[:no_candidates] ? nil : group[:pick]
    {
      label: group[:label].to_s,
      no_candidates: !!group[:no_candidates],
      reason: group[:no_candidates] ? nil : build_reason_text(group),
      badge: pick ? {
        text: "$#{fmt_price(pick[:strike])} / #{pick[:expiration_date]}",
        delta_text: "Delta #{fmt_decimal(pick[:delta], 3)}",
        color: pdf_signal_rgb_for_tier(pick[:liquidity_tier].to_s)
      } : nil
    }
  end


  # 理由文字目前是分段 plain 呼叫組成畫面，PDF 需要純文字版本；用同一組資料
  # 重建等義文字（不重算數值，只重組顯示字串），避免維護兩份理由生成邏輯。
  def build_reason_text(group)
    pick = group[:pick]
    return nil unless pick
    parts = []
    parts << "建議到期日：#{pick[:expiration_date]}（DTE #{pick[:dte].to_i}），履約價 $#{fmt_strike_short(pick[:strike])}，Delta #{fmt_decimal(pick[:delta], 3)}，Mid $#{fmt_price(pick[:mid])}。"
    if group[:runner_up]
      ru = group[:runner_up]
      parts << "此履約價 OI 為 #{fmt_int(pick[:open_interest])}，為此天期區間最高；次選履約價 $#{fmt_strike_short(ru[:strike])}（#{ru[:expiration_date]}）OI 為 #{fmt_int(ru[:open_interest])}，流動性相對較差。"
    else
      parts << "此天期區間僅此一個候選，OI 為 #{fmt_int(pick[:open_interest])}。"
    end
    parts << "Time Value 溢價約 #{fmt_pct(pick[:time_value_pct])}（相較直接持股多負擔的時間價值成本）。" if pick[:time_value_pct]
    if pick[:bid_ask_spread_pct]
      parts << (pick[:bid_ask_spread_pct].to_f > 0.05 ?
        "⚠ Bid-Ask Spread 偏高（#{fmt_pct(pick[:bid_ask_spread_pct])}），進出場成本較大，建議使用限價單。" :
        "Bid-Ask Spread #{fmt_pct(pick[:bid_ask_spread_pct])}，進出場成本合理。")
    end
    parts << "IV #{fmt_pct(pick[:iv])}，Vega #{fmt_decimal(pick[:vega], 4)}；若未來 IV 回落，每個百分點 IV 變化對此合約的影響約為 Vega 值，需留意 IV Crush 風險。" if pick[:vega]
    parts << "⚠ 注意：此天期區間所有候選均有「近期無成交」警示，目前市場成交清淡，進出場可能有困難。" if group[:all_warned]
    parts.join("\n")
  end


  def pdf_candidate_row(row)
    tier = row[:liquidity_tier].to_s
    {
      expiration_date: row[:expiration_date].to_s,
      dte:             fmt_int(row[:dte]),
      strike:          fmt_price(row[:strike]),
      delta:           fmt_decimal(row[:delta], 4),
      oi:              fmt_int(row[:open_interest]),
      volume:          fmt_int(row[:volume]),
      liquidity:       tier + (row[:no_recent_volume_warning] ? "（⚠無成交）" : ""),
      liquidity_rgb:   pdf_signal_rgb_for_tier(tier),
      bid:             fmt_price(row[:bid]),
      ask:             fmt_price(row[:ask]),
      mid:             fmt_price(row[:mid]),
      spread:          fmt_pct(row[:bid_ask_spread_pct]),
      intrinsic:       fmt_price(row[:intrinsic_value]),
      extrinsic:       fmt_price(row[:extrinsic_value]),
      extrinsic_pct:   fmt_pct(row[:extrinsic_pct]),
      time_value_pct:  fmt_pct(row[:time_value_pct]),
      iv:              fmt_pct(row[:iv]),
      vega:            fmt_decimal(row[:vega], 4),
      itm_prob:        fmt_pct(row[:itm_probability])
    }
  end


  def pdf_flow_row(t)
    dir = (t[:direction] || "neutral").to_s
    # 與 render_flow_row 的 fallback 邏輯一致：分類器產出的細分類值
    # （bullish_directional／indeterminate 等）不在 DIR_STYLE 三個 key 內時，
    # 一律 fallback 顯示「中性」，不要漏掉這層 fallback 讓 PDF 顯示原始分類字串。
    style = DIR_STYLE[dir] || DIR_STYLE["neutral"]
    {
      type:          t[:option_type].to_s,
      strike:        fmt_price(t[:strike]),
      expires:       t[:expires_at].to_s,
      dte:           t[:dte].to_s,
      delta:         fmt_decimal(t[:delta], 3),
      code:          t[:trade_condition].to_s,
      size:          fmt_int(t[:size]),
      side:          t[:side].to_s,
      premium:       fmt_premium(t[:premium]),
      direction:     style[:label],
      direction_rgb: pdf_signal_rgb_for_direction(DIR_STYLE.key(style))
    }
  end


  def render_pdf_data_script
    script(type: "application/json", id: "leaps-pdf-data") { raw pdf_export_payload.to_json.html_safe }
  end
end
