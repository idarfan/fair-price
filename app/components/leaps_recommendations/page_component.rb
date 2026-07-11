# frozen_string_literal: true

class LeapsRecommendations::PageComponent < ApplicationComponent
  LIQUIDITY_STYLE = {
    "充足" => SIGNAL_COLORS[:confirm_bull],
    "普通" => SIGNAL_COLORS[:caution],
    "偏低" => SIGNAL_COLORS[:warning]
  }.freeze

  DIR_STYLE = {
    "bullish" => SIGNAL_COLORS[:confirm_bull].merge(label: "偏多").freeze,
    "bearish" => SIGNAL_COLORS[:confirm_bear].merge(label: "偏空").freeze,
    "neutral" => SIGNAL_COLORS[:neutral].merge(label: "中性").freeze
  }.freeze

  TABLE_COLS = [
    "到期日", "DTE", "履約價", "Delta", "OI", "Volume", "流動性判斷",
    "Bid", "Ask", "Mid", "Spread%", "內在價值", "外在價值", "外在佔比", "Time Value%", "IV", "Vega", "被指派機率"
  ].freeze

  # PMCC v3 §9.1：12 個關鍵欄常駐顯示，其餘（Bid/Ask、Gamma/Theta/Vega/Moneyness/
  # Theoretical/ITM Prob/Vol/OI/Vol-OI/OI Chg、MaxProfit未收租、未年化收租率）
  # 放進每列的 details/summary 展開區。
  PMCC_TABLE_COLS = [
    "KL", "PL(mid)", "Long DTE", "Long Δ",
    "KS", "PS(mid)", "Short Δ",
    "Spread", "NetDebit", "MaxProfit(含SC)", "年化收租率",
    "Golden Rule"
  ].freeze

  TABLE_RIGHT_ALIGN_COLS = (
    %w[DTE Delta OI Volume Bid Ask Mid IV Vega] +
    [ "履約價", "Spread%", "內在價值", "外在價值", "外在佔比", "Time Value%", "被指派機率" ]
  ).freeze

  FLOW_COLS = [ "類型", "履約價", "到期日", "DTE", "Delta", "Code", "Size", "Side", "Premium", "方向" ].freeze

  # 術語字卡（leaps-column-tooltips-spec.md「術語字卡區」）：15 張，音標依 instruction 逐字，
  # 背面文案沿用 LEAPS_COL_EXPLAIN 觀點擴寫（買方視角），例子取自本頁實測資料。
  VOCAB_CARDS = [
    { en: "LEAPS", ipa: "/liːps/", zh: "長天期選擇權", hint: "Long-term Equity AnticiPation Securities",
      back: "到期日一年以上的選擇權，時間緩衝大，適合取代持股做方向部位；本表只列 DTE ≥ 364 的合約。",
      ex: "例：2028-01-21 到期、DTE 568 天的 Call 就是 LEAPS。" },
    { en: "Strike Price", ipa: "/straɪk praɪs/", zh: "履約價", hint: "你約定買入股票的價格",
      back: "Call 買方有權以履約價買入正股；履約價越低於現價越深價內，行為越接近持有正股。",
      ex: "例：現價 $14.46 時，$10 Call 已深入價內 $4.46。" },
    { en: "Delta", ipa: "/ˈdɛltə/", zh: "方向敏感度", hint: "股價動 $1，權利金動多少",
      back: "股價每動 $1，權利金理論上變動 Delta 元；也近似到期價內機率。本表篩 0.60–0.90 的深價內區間。",
      ex: "例：Delta 0.85 的 Call，股價 +$1 → 權利金約 +$0.85。" },
    { en: "Open Interest", ipa: "/ˈoʊpən ˈɪntrəst/", zh: "未平倉量", hint: "市場上還活著的合約數",
      back: "尚未平倉的合約總數，只在盤後更新；是本表排序主鍵，OI 越高通常越容易進出。",
      ex: "例：OI 8,273 的檔位遠比 OI 349 的容易成交。" },
    { en: "Volume", ipa: "/ˈvɑːljuːm/", zh: "成交量", hint: "今天實際成交了幾口",
      back: "當日即時成交口數。OI 高但 Volume 長期為零，實際進出仍可能困難，要搭配著看。",
      ex: "例：Volume 145、OI 8,273 → Vol/OI ≈ 0.018，近期交投清淡。" },
    { en: "Bid", ipa: "/bɪd/", zh: "買價", hint: "市場願意付的最高價",
      back: "掛單簿上的最高買價，是你「賣出」時的底價參考；市價賣出約落在 Bid 附近。",
      ex: "例：Bid 8.70／Ask 9.95 時，市價賣出約拿 $8.70。" },
    { en: "Ask", ipa: "/æsk/", zh: "賣價", hint: "市場願意賣的最低價",
      back: "掛單簿上的最低賣價，是你「買入」時的天花板參考；直接市價買會付到 Ask。",
      ex: "例：市價買付 $9.95，掛 Mid 約可省 $0.63。" },
    { en: "Mid Price", ipa: "/mɪd praɪs/", zh: "中間價", hint: "(Bid+Ask)/2，掛單參考",
      back: "Bid 與 Ask 的中點，掛限價單的參考價；本系統所有衍生欄位一律以 Mid 為權利金基準。",
      ex: "例：Bid 8.70／Ask 9.95 → Mid 9.325。" },
    { en: "Spread", ipa: "/sprɛd/", zh: "買賣價差", hint: "一次進出的滑價成本",
      back: "Ask−Bid 的距離；深價內 LEAPS 常偏寬，Spread% 超過 10% 進出成本明顯，建議用限價單。",
      ex: "例：(9.95−8.70)/9.325 ≈ 13.4%，偏寬。" },
    { en: "Intrinsic Value", ipa: "/ɪnˈtrɪnsɪk ˈvæljuː/", zh: "內在價值", hint: "已經在錢裡的部分",
      back: "max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不會流失。",
      ex: "例：現價 14.46、履約價 10 → 內在 $4.46。" },
    { en: "Extrinsic Value", ipa: "/ɛkˈstrɪnsɪk ˈvæljuː/", zh: "外在價值", hint: "付出去的保險費",
      back: "Mid−內在價值，時間＋波動率溢價；隨時間流逝與 IV 回落而流失，是買方的主要成本。",
      ex: "例：Mid 9.325−內在 4.46 → 外在 $4.865，佔比 52%。" },
    { en: "Implied Volatility", ipa: "/ɪmˈplaɪd ˌvɑːləˈtɪləti/", zh: "隱含波動率", hint: "市場預期的波動大小",
      back: "由市場價格反推的預期波動；IV 越高權利金越貴，買方在高 IV 位進場要小心回落侵蝕。",
      ex: "例：IV 121.7% 屬極高水位，外在價值特別肥。" },
    { en: "Vega", ipa: "/ˈveɪɡə/", zh: "IV 敏感度", hint: "IV 動 1%，權利金動多少",
      back: "IV 每變 1% 權利金的理論變化；DTE 越長 Vega 越大，LEAPS 買方天然是 Vega 多頭。",
      ex: "例：Vega 0.0418 → IV 回落 10%，權利金約損失 $0.42。" },
    { en: "IV Crush", ipa: "/aɪ viː krʌʃ/", zh: "波動率回落", hint: "外在價值的瞬間蒸發",
      back: "IV 快速下降造成外在價值蒸發（常見於財報後）；高 IV 買入 LEAPS 的主要風險之一。",
      ex: "例：IV 120% → 80%，Vega 0.04 → 約損 $1.6。" },
    { en: "Assignment", ipa: "/əˈsaɪnmənt/", zh: "被指派", hint: "到期價內就會發生",
      back: "賣方被要求履約；買方視角對應「行權」。本表「被指派機率」欄＝Barchart 估的到期價內機率。",
      ex: "例：ITM Prob 59.6% ≈ 六成機率到期仍在價內。" }
  ].freeze

  # 欄位教學（leaps-column-tooltips-spec.md）：與上面兩個欄位陣列一一對齊的 tip key。
  # freeze 前斷言長度，防止未來加欄位時漏同步導致文案錯位。
  TABLE_COL_KEYS = %w[
    expiration dte strike delta oi volume liquidity bid ask mid spread
    intrinsic extrinsic extrinsic_pct time_value_pct iv vega itm_prob
  ].freeze
  FLOW_COL_KEYS = %w[
    f_type f_strike f_expiration f_dte f_delta f_code f_size f_side f_premium f_direction
  ].freeze
  raise "TABLE_COL_KEYS 與 TABLE_COLS 長度不一致" unless TABLE_COL_KEYS.size == TABLE_COLS.size
  raise "FLOW_COL_KEYS 與 FLOW_COLS 長度不一致"   unless FLOW_COL_KEYS.size == FLOW_COLS.size

  # 使用者回報：PMCC 表格桶內排序只依 max_profit，不能依 KS 瀏覽——需求擴大為
  # LEAPS 排行表跟 PMCC 表都要能點表頭切換排序鍵。跟 TABLE_COL_KEYS 一樣一一對齊。
  PMCC_TABLE_COL_KEYS = %w[
    kl pl long_dte long_delta ks ps short_delta spread net_debit max_profit yield_ann passes
  ].freeze
  raise "PMCC_TABLE_COL_KEYS 與 PMCC_TABLE_COLS 長度不一致" unless PMCC_TABLE_COL_KEYS.size == PMCC_TABLE_COLS.size

  def initialize(symbol: nil, candidates: [], recommendation: nil, flow_panel: nil, scrape_status: nil, scrape_errors: [], user_strike: nil, next_earnings: nil, pmcc_ranking: nil)
    @symbol         = symbol
    @candidates     = Array(candidates)
    @recommendation = recommendation
    @flow_panel     = flow_panel
    @scrape_status  = scrape_status
    @scrape_errors  = Array(scrape_errors)
    @user_strike    = user_strike
    @next_earnings  = next_earnings
    # PMCC v3 §9：render_pmcc_section／render_pmcc_edu_section 見 Step7；
    # 這裡先接住參數，讓 Step6 controller 改動不會因為未知 kwarg 直接炸掉。
    @pmcc_ranking   = pmcc_ranking
  end

  def view_template
    div(id: "leaps-export-root", class: "space-y-6",
        data_pdf_font_url: helpers.asset_path("NotoSansTC-Regular-subset-v39.ttf"),
        data_pdf_ipa_font_url: helpers.asset_path("NotoSans-Regular-ipa-subset-v42.ttf")) do
      render_header
      render_search_form
      render_status_bar if @scrape_status
      if @candidates.any?
        render_recommendation if @recommendation
        render_ranking_table
        render_flow_panel if @flow_panel
        render_pmcc_section
      end
      render_pmcc_edu_section
      render_vocab_cards
    end
    render_pdf_data_script
    render_loading_script
    render_export_script
    render_vector_pdf_script
    # 排序腳本必須先於教學 popover 腳本註冊：兩者都用 document 委派 click，
    # 排序點擊區域（.sort-arrow）若被教學腳本先攔截，會同時彈出 popover
    # 又觸發排序（實測發現的真實 bug）。排序腳本命中 .sort-arrow 時呼叫
    # stopImmediatePropagation，越早註冊才能真的擋住後面的教學腳本監聽器。
    render_sortable_table_script
    render_tooltips_script
  end

  private

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
        "本表只挑 Delta 0.60–0.90 的深價內合約：太低（Delta 太小）槓桿雖高但方向不夠貼近正股、時間價值佔比也高；太高（Delta 逼近 1）則買進成本已經很接近正股，槓桿效益變小。DTE #{dte} 天——天期越長，同一履約價的 Delta 通常越往中間值靠攏（時間價值稀釋方向性），這也是「深價內＋長天期」要挑履約價再往下修正緩衝的原因。"
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

  # PDF（autotable）不能用 Tailwind class，改用等義 hex 值；語義選擇仍走既有
  # LIQUIDITY_STYLE / DIR_STYLE 的 key（tier / direction），只有顏色的「表示法」
  # 從 class 換成 hex，語義對應本身沒有另造一套。
  PDF_SIGNAL_HEX = {
    confirm_bull: { bg: "#f0fdf4", border: "#86efac", text: "#166534", dot: "#4ade80" },
    caution:      { bg: "#fefce8", border: "#fde047", text: "#854d0e", dot: "#facc15" },
    warning:      { bg: "#fff7ed", border: "#fdba74", text: "#9a3412", dot: "#fb923c" },
    confirm_bear: { bg: "#fef2f2", border: "#fca5a5", text: "#991b1b", dot: "#f87171" },
    neutral:      { bg: "#f9fafb", border: "#d1d5db", text: "#4b5563", dot: "#9ca3af" }
  }.freeze

  def pdf_signal_rgb_for_tier(tier)
    key = case tier
    when "充足" then :confirm_bull
    when "普通" then :caution
    when "偏低" then :warning
    else :neutral
    end
    PDF_SIGNAL_HEX[key]
  end

  def pdf_signal_rgb_for_direction(dir)
    key = case dir
    when "bullish" then :confirm_bull
    when "bearish" then :confirm_bear
    else :neutral
    end
    PDF_SIGNAL_HEX[key]
  end

  def render_pdf_data_script
    script(type: "application/json", id: "leaps-pdf-data") { raw pdf_export_payload.to_json.html_safe }
  end

  # 使用者回報：PMCC 表格桶內排序只依 max_profit 一種，不能依 KS 瀏覽——擴大成
  # LEAPS 排行表 + PMCC 表都能點表頭切換排序鍵。一支通用 JS，靠 table 上的
  # data-sortable + th 上的 data-sort-key + tr 上的 data-sort-json（每列一份
  # {key: 數值} JSON）就能運作，不用替兩張表各寫一份。
  def render_sortable_table_script
    script do
      raw <<~JS.html_safe
        (function () {
          function getVal(tr, key) {
            var raw = tr.getAttribute('data-sort-json');
            if (!raw) return null;
            try {
              var obj = JSON.parse(raw);
              var v = obj[key];
              if (v === null || v === undefined) return null;
              var f = parseFloat(v);
              return isFinite(f) ? f : null;
            } catch (e) { return null; }
          }

          function sortTable(table, key, dir) {
            var tbody = table.querySelector('tbody');
            if (!tbody) return;
            var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
            var floor = -Infinity;
            rows.sort(function (a, b) {
              var av = getVal(a, key);
              var bv = getVal(b, key);
              av = av === null ? floor : av;
              bv = bv === null ? floor : bv;
              return dir === 'asc' ? av - bv : bv - av;
            });
            rows.forEach(function (r) { tbody.appendChild(r); });
          }

          document.addEventListener('click', function (e) {
            // 命中排序圖示（.sort-arrow）才處理，且用 stopImmediatePropagation
            // 擋掉後面才註冊的教學 popover 委派——同一個 th 上還有 data-tip-key，
            // 兩層委派都掛在 document，若不擋，點排序圖示會同時彈出教學 popover。
            var arrow = e.target.closest('.sort-arrow[data-sort-key]');
            if (!arrow) return;
            e.stopImmediatePropagation();

            var table = arrow.closest('table[data-sortable]');
            if (!table) return;

            var key     = arrow.getAttribute('data-sort-key');
            var curDir  = arrow.getAttribute('data-sort-dir');
            var nextDir = curDir === 'desc' ? 'asc' : 'desc';

            table.querySelectorAll('.sort-arrow[data-sort-key]').forEach(function (a) {
              if (a === arrow) return;
              a.removeAttribute('data-sort-dir');
              a.textContent = '⇅';
            });

            arrow.setAttribute('data-sort-dir', nextDir);
            arrow.textContent = nextDir === 'desc' ? '▾' : '▴';

            sortTable(table, key, nextDir);
          });
        })();
      JS
    end
  end

  def render_header
    div(class: "flex items-start justify-between gap-4") do
      div do
        h1(class: "text-xl font-bold text-gray-900") { plain "LEAPS Call 候選排行" }
        p(class: "text-sm text-gray-500 mt-0.5") { plain "Delta 0.60–0.90 深度價內 Call · 依 OI 由高到低排序" }
      end
      # 匯出按鈕：data-export-exclude 讓 html-to-image filter 把按鈕排除在輸出畫面外；
      # 無資料時 disabled，避免匯出空頁。
      div(class: "flex items-center gap-2", data_export_exclude: "") do
        render_tour_button
        render_export_button("png", "匯出 PNG")
        render_export_button("pdf", "匯出 PDF")
      end
    end
  end

  def render_tour_button
    exportable = @candidates.any?
    base  = "px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap"
    style = exportable ?
      "border-gray-300 bg-white text-gray-700 hover:bg-gray-50" :
      "border-gray-200 bg-gray-100 text-gray-400 cursor-not-allowed"
    button(id: "leaps-tour-btn", type: "button", disabled: !exportable,
           class: "#{base} #{style}") { plain "欄位導覽" }
  end

  def render_export_button(kind, label)
    exportable = @candidates.any?
    base  = "px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap"
    style = exportable ?
      "border-gray-300 bg-white text-gray-700 hover:bg-gray-50" :
      "border-gray-200 bg-gray-100 text-gray-400 cursor-not-allowed"
    button(
      id: "leaps-export-#{kind}", type: "button",
      data_leaps_export: kind, disabled: !exportable,
      class: "#{base} #{style}"
    ) { plain label }
  end

  def render_search_form
    form(id: "leaps-form", action: "/leaps", method: "get", class: "flex items-center gap-3 flex-wrap") do
      input(
        id: "leaps-symbol-input", type: "text", name: "symbol",
        value: @symbol.to_s, placeholder: "股票代號，例如 NOK",
        maxlength: "10",
        class: "w-40 px-4 py-2 rounded-lg border border-gray-300 text-sm font-mono uppercase " \
               "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
      )
      div(class: "flex items-center gap-1.5") do
        label(for: "leaps-strike-input", class: "text-xs text-gray-500 whitespace-nowrap") { plain "履約價（選填）" }
        input(
          id: "leaps-strike-input", type: "number", name: "user_strike",
          value: @user_strike.to_s, placeholder: "自動",
          min: "0.01", step: "any",
          class: "w-24 px-3 py-2 rounded-lg border border-gray-300 text-sm " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
        )
      end
      button(
        id: "leaps-submit-btn", type: "submit",
        class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
      ) { plain "查詢" }
      div(id: "leaps-loading", class: "hidden items-center gap-2 text-sm text-gray-500") do
        div(class: "w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin")
        plain "抓取資料中，請稍候…（約 3–5 分鐘）"
      end
    end
    div(id: "leaps-strike-error",
        class: "hidden text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2 mt-1")
  end

  def render_status_bar
    case @scrape_status
    when :session_expired
      render_alert("bg-orange-50 border border-orange-300 text-orange-800",
        "⚠️ 請先登入 Barchart 後重試。（Barchart 登入 Session 已過期）")
    when :partial_error
      expired_s  = partial_error_strike
      rec_strikes = recommendation_strikes
      if expired_s && rec_strikes.any? && !rec_strikes.any? { |s| s.to_f == expired_s }
        rec_list = rec_strikes.map { |s| "Strike #{fmt_strike_short(s)}" }.join("、")
        render_alert("bg-yellow-50 border border-yellow-300 text-yellow-800",
          "⚠️ Strike #{fmt_strike_short(expired_s)} 的 V&G 資料不完整，但不影響本次推薦（推薦候選為 #{rec_list}）")
      else
        msg = @scrape_errors.first || "抓取中途發生未預期錯誤，部分資料可能不完整，請重新查詢。"
        render_alert("bg-yellow-50 border border-yellow-300 text-yellow-800", "⚠️ #{msg}")
      end
    when :cdp_offline
      render_alert("bg-red-50 border border-red-300 text-red-800",
        "❌ CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動。若電腦曾經睡眠/喚醒，這通常是 WSL2 的 /mnt/c/ 掛載失效造成的，請在 Windows PowerShell 執行 wsl --shutdown 後等待 WSL2 重新啟動，再重試一次。")
    when :error
      msg = @scrape_errors.first.presence || "抓取時發生未知錯誤，請稍後重試。"
      render_alert("bg-red-50 border border-red-300 text-red-800", "❌ #{msg}")
    when :no_candidates
      msg = @user_strike.present? ?
        "這個履約價 #{@user_strike}（含緩衝檔）在所有到期日都沒有符合 Delta 0.60–0.90 的候選。請嘗試其他履約價，或留空讓系統自動偵測。" :
        "目前沒有符合篩選條件的候選，請嘗試調整 Delta 範圍或手動輸入履約價後重試。"
      render_alert("bg-orange-50 border border-orange-300 text-orange-800", "⚠️ #{msg}")
    when :invalid_strike
      msg = @scrape_errors.first.presence || "履約價不在有效範圍，請重新輸入。"
      render_alert("bg-red-50 border border-red-300 text-red-800", "❌ #{msg}")
    when :ready_to_fetch
      render_alert("bg-blue-50 border border-blue-300 text-blue-800",
        "ℹ️ 尚未取得 #{@symbol} 的 LEAPS 資料，請點「查詢」開始抓取。")
    end
  end

  def render_alert(class_str, msg)
    div(class: "px-4 py-3 rounded-lg text-sm #{class_str}") { plain msg }
  end

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
        plain "本表只挑 Delta 0.60–0.90 的深價內合約：太低（Delta 太小）槓桿雖高但方向不夠貼近正股、時間價值佔比也高；太高（Delta 逼近 1）則買進成本已經很接近正股，槓桿效益變小。DTE #{dte} 天——天期越長，同一履約價的 Delta 通常越往中間值靠攏（時間價值稀釋方向性），這也是「深價內＋長天期」要挑履約價再往下修正緩衝的原因。"
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

  def render_ranking_table
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50") do
        h2(class: "text-sm font-semibold text-gray-700") { plain "LEAPS 候選排行 — #{@symbol}" }
        p(class: "text-xs text-gray-400 mt-0.5") do
          plain "依 OI 由高到低排序；流動性判斷依本次查詢候選的 OI 相對排名計算，非固定門檻，不同標的會自動調整基準。"
        end
      end
      div(class: "overflow-x-auto") do
        table(class: "w-full text-xs text-gray-700", data_sortable: "true") do
          thead(class: "bg-gray-50 text-gray-500 text-xs") do
            tr do
              TABLE_COLS.each_with_index do |col, idx|
                key = TABLE_COL_KEYS[idx]
                if key == "expiration" # 日期字串，不參與數值排序
                  th(id: "leaps-th-#{key}", data_tip_key: key,
                     class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain col }
                else
                  # data-sort-key 故意放在內層排序圖示，不放在 th 本身——th 上還有
                  # data-tip-key（點擊會開欄位教學 popover），兩個 click 委派都掛在
                  # document 上，若共用同一個點擊區域，點表頭會同時觸發排序跟教學
                  # popover（實測發現的真的 bug，不是假設）。分開兩個可點擊區域，
                  # 互不干擾：點文字＝看說明（沿用既有行為不變），點 ⇅ 圖示＝排序。
                  th(id: "leaps-th-#{key}", data_tip_key: key,
                     class: "px-3 py-2 text-center font-medium whitespace-nowrap") do
                    plain col
                    span(class: "sort-arrow ml-0.5 text-gray-400 cursor-pointer hover:text-blue-600 select-none",
                         data_sort_key: key) { plain "⇅" }
                  end
                end
              end
            end
          end
          tbody do
            @candidates.each_with_index { |row, i| render_candidate_row(row, i) }
          end
        end
      end
      div(class: "px-4 py-2 border-t border-gray-100 bg-gray-50") do
        p(class: "text-xs text-gray-400") do
          plain "以上為 Delta 區間篩選後的排行結果，僅供策略篩選參考，非投資建議，請自行評估。"
        end
      end
    end
  end

  def render_candidate_row(row, i)
    tier  = row[:liquidity_tier].to_s
    style = LIQUIDITY_STYLE[tier] || LIQUIDITY_STYLE["普通"]
    warn  = row[:no_recent_volume_warning]

    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{i.odd? ? 'bg-gray-50/50' : ''}",
       data_sort_json: leaps_row_sort_json(row, tier)) do
      td(class: "px-3 py-2 text-center font-mono whitespace-nowrap") { plain row[:expiration_date].to_s }
      td(class: "px-3 py-2 text-center")                             { plain row[:dte].to_s }
      td(class: "px-3 py-2 text-center font-semibold")               { plain fmt_price(row[:strike]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_decimal(row[:delta], 4) }
      td(class: "px-3 py-2 text-center font-semibold")               { plain fmt_int(row[:open_interest]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_int(row[:volume]) }
      td(class: "px-3 py-2 text-center") do
        div(class: "inline-flex flex-row items-center gap-1.5") do
          span(class: "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs " \
                       "#{style[:bg]} #{style[:text]} border #{style[:border]}") do
            div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{style[:dot]}")
            plain tier
          end
          if warn
            span(class: "text-orange-600 text-xs whitespace-nowrap") { plain "⚠ 近期無成交" }
          end
        end
      end
      td(class: "px-3 py-2 text-center") { plain fmt_price(row[:bid]) }
      td(class: "px-3 py-2 text-center") { plain fmt_price(row[:ask]) }
      td(class: "px-3 py-2 text-center") { plain fmt_price(row[:mid]) }
      td(class: "px-3 py-2 text-center") { plain fmt_pct(row[:bid_ask_spread_pct]) }
      td(class: "px-3 py-2 text-center") { plain fmt_price(row[:intrinsic_value]) }
      td(class: "px-3 py-2 text-center") { plain fmt_price(row[:extrinsic_value]) }
      td(class: "px-3 py-2 text-center font-semibold") { plain fmt_pct(row[:extrinsic_pct]) }
      td(class: "px-3 py-2 text-center") { plain fmt_pct(row[:time_value_pct]) }
      td(class: "px-3 py-2 text-center") { plain fmt_pct(row[:iv]) }
      td(class: "px-3 py-2 text-center") { plain fmt_decimal(row[:vega], 4) }
      td(class: "px-3 py-2 text-center") { plain fmt_pct(row[:itm_probability]) }
    end
  end

  def render_flow_panel
    return unless @flow_panel&.dig(:status) == :ok

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex justify-between items-center") do
        div do
          h2(class: "text-base font-semibold text-gray-700") { plain "Options Flow — 情緒參考，非排序依據" }
          p(class: "text-xs text-gray-500 mt-0.5") do
            plain "#{@flow_panel[:date]} · 前 20 大成交（依 Premium 降序）"
          end
        end
        div(class: "text-sm font-medium whitespace-nowrap pl-4") do
          span(class: "text-green-600") { plain "Call #{fmt_premium(@flow_panel[:call_premium_total])}" }
          span(class: "text-gray-400 mx-1") { plain "·" }
          span(class: "text-red-500") { plain "Put #{fmt_premium(@flow_panel[:put_premium_total])}" }
        end
      end

      render_highlighted if @flow_panel[:highlighted_trades]&.any?
      render_large_orders
    end
  end

  def render_highlighted
    div(class: "px-4 py-3 bg-blue-50 border-b border-blue-100") do
      p(class: "text-xs font-semibold text-blue-700 mb-1.5") { plain "排行候選 × 今日 Flow 重疊" }
      @flow_panel[:highlighted_trades].each do |hit|
        p(class: "text-xs text-blue-600") do
          plain "排行 ##{hit[:rank]} · $#{sprintf('%.2f', hit[:candidate_strike].to_f)} / " \
                "#{hit[:candidate_expiry]} — #{hit[:trades].size} 筆匹配"
        end
      end
    end
  end

  def render_large_orders
    orders = @flow_panel[:large_orders]
    return unless orders&.any?

    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs text-gray-700") do
        thead(class: "bg-gray-50 text-gray-500 text-xs") do
          tr do
            FLOW_COLS.each_with_index do |col, idx|
              key = FLOW_COL_KEYS[idx]
              th(id: "leaps-th-#{key}", data_tip_key: key, class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain col }
            end
          end
        end
        tbody do
          orders.each_with_index { |t, i| render_flow_row(t, i) }
        end
      end
    end
  end

  def render_flow_row(t, i = 0)
    dir   = (t[:direction] || "neutral").to_s
    ds    = DIR_STYLE[dir] || DIR_STYLE["neutral"]
    is_call = t[:option_type].to_s == "Call"
    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{i.odd? ? 'bg-gray-50/50' : ''}") do
      td(class: "px-3 py-2 text-center font-medium #{is_call ? 'text-green-700' : 'text-red-700'}") { plain t[:option_type].to_s }
      td(class: "px-3 py-2 text-center font-mono")              { plain fmt_price(t[:strike]) }
      td(class: "px-3 py-2 text-center font-mono text-xs")      { plain t[:expires_at].to_s }
      td(class: "px-3 py-2 text-center")                        { plain t[:dte].to_s }
      td(class: "px-3 py-2 text-center")                        { plain fmt_decimal(t[:delta], 3) }
      td(class: "px-3 py-2 text-center text-gray-500")          { plain t[:trade_condition].to_s }
      td(class: "px-3 py-2 text-center")                        { plain fmt_int(t[:size]) }
      td(class: "px-3 py-2 text-center")                        { plain t[:side].to_s }
      td(class: "px-3 py-2 text-center font-semibold")          { plain fmt_premium(t[:premium]) }
      td(class: "px-3 py-2 text-center") do
        div(class: "inline-flex items-center gap-1") do
          div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{ds[:dot]}")
          span(class: "#{ds[:text]}") { plain ds[:label] }
        end
      end
    end
  end

  # ── PMCC v3 §9.1: 黃金法則組合表 ──────────────────────────────────────────────

  def render_pmcc_section
    return unless @pmcc_ranking

    status = @pmcc_ranking[:status]

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex justify-between items-center flex-wrap gap-2") do
        div do
          h2(class: "text-base font-semibold text-gray-700") { plain "⚖️ PMCC黃金法則組合 — #{@symbol}" }
          p(class: "text-xs text-gray-500 mt-0.5") { plain "PL < KS−KL · 每到期日前 5" }
        end
        if status == :ok
          summary = @pmcc_ranking[:summary]
          div(class: "text-sm font-medium whitespace-nowrap") do
            plain "總組合 #{summary[:total_combos]} / 通過 #{summary[:passing_combos]}"
          end
        end
      end

      case status
      when :no_leaps, :no_short, :no_data
        div(class: "px-4 py-6 text-center text-sm text-gray-400") { plain "尚無 Short Call 資料，請重新查詢" }
      when :ok
        div(class: "divide-y divide-gray-100") do
          @pmcc_ranking[:summary][:expirations].each_with_index do |exp_key, idx|
            render_pmcc_bucket(exp_key, @pmcc_ranking[exp_key], idx)
          end
        end
      end
    end
  end

  PMCC_TERM_LABELS = [ "近月", "中月", "遠月" ].freeze

  def render_pmcc_bucket(exp_key, bucket, idx)
    div(class: "px-4 py-4") do
      div(class: "flex items-center gap-2 flex-wrap mb-2") do
        h3(class: "text-sm font-semibold text-gray-700") do
          plain "#{bucket[:expiration]} · #{bucket[:short_dte]} DTE"
        end
        term = PMCC_TERM_LABELS[idx]
        span(class: "text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-500") { plain term } if term
        if bucket[:short_dte].to_i.positive? && bucket[:short_dte].to_i < 19
          span(class: "text-xs px-2 py-0.5 rounded-full bg-orange-50 text-orange-800 border border-orange-300") do
            plain "⚠️ 短於 lesson9 建議區間（19–45 天）：Gamma 風險高、被指派機率陡增、收租金額低"
          end
        end
      end

      if bucket[:combos].empty?
        div(class: "text-xs text-gray-400 py-2") { plain "此到期日無 KS>KL 組合" }
      else
        render_pmcc_table(bucket[:combos])
      end
    end
  end

  def render_pmcc_table(combos)
    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs text-gray-700", data_sortable: "true") do
        thead(class: "bg-gray-50 text-gray-500 text-xs") do
          tr do
            PMCC_TABLE_COLS.each_with_index do |col, idx|
              key = PMCC_TABLE_COL_KEYS[idx]
              th(class: "px-3 py-2 text-center font-medium whitespace-nowrap") do
                plain col
                span(class: "sort-arrow ml-0.5 text-gray-400 cursor-pointer hover:text-blue-600 select-none",
                     data_sort_key: key) { plain "⇅" }
              end
            end
            th(class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain "詳細" }
          end
        end
        tbody do
          combos.each_with_index { |combo, i| render_pmcc_combo_row(combo, i) }
        end
      end
    end
  end

  def render_pmcc_combo_row(combo, i)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    fail_row  = !combo[:passes_golden_rule]
    row_bg    = fail_row ? "bg-red-50" : (i.odd? ? "bg-gray-50/50" : "")

    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{row_bg}",
       data_sort_json: pmcc_combo_sort_json(combo)) do
      td(class: "px-3 py-2 text-center font-semibold text-blue-600") { plain fmt_price(long_leg[:strike]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(long_leg[:mid]) }
      td(class: "px-3 py-2 text-center")                             { plain long_leg[:dte].to_s }
      td(class: "px-3 py-2 text-center")                             { render_pmcc_delta_cell(long_leg[:delta], combo[:leaps_delta_ok]) }
      td(class: "px-3 py-2 text-center font-semibold text-red-600")  { plain fmt_price(short_leg[:strike]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(short_leg[:mid]) }
      td(class: "px-3 py-2 text-center")                             { render_pmcc_delta_cell(short_leg[:delta], combo[:short_delta_ok]) }
      td(class: "px-3 py-2 text-center #{pmcc_signed_color(combo[:spread])}")     { plain fmt_price(combo[:spread]) }
      td(class: "px-3 py-2 text-center")                             { plain fmt_price(combo[:net_debit]) }
      td(class: "px-3 py-2 text-center font-semibold #{pmcc_signed_color(combo[:max_profit])}") { plain fmt_price(combo[:max_profit]) }
      td(class: "px-3 py-2 text-center font-semibold")               { plain fmt_pmcc_pct(combo[:premium_yield_ann]) }
      td(class: "px-3 py-2 text-center") { render_pmcc_verdict_cell(combo) }
      td(class: "px-3 py-2 text-center") { render_pmcc_details_cell(combo) }
    end
  end

  def render_pmcc_delta_cell(delta, ok)
    span(class: ok ? "text-green-700 font-semibold" : "text-gray-600") do
      plain fmt_decimal(delta, 3)
      plain " ✅" if ok
    end
  end

  def render_pmcc_verdict_cell(combo)
    if combo[:passes_golden_rule]
      span(class: "text-green-700 font-semibold whitespace-nowrap") { plain "✅ 通過" }
    else
      div(class: "flex flex-col items-center gap-0.5 max-w-[160px]") do
        span(class: "text-red-700 font-semibold") { plain "❌" }
        span(class: "text-red-500 text-[10px] leading-tight whitespace-normal") { plain combo[:fail_reason] }
      end
    end
  end

  def render_pmcc_details_cell(combo)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    td_class  = "px-3 py-2 text-center"

    details(class: "inline-block text-left") do
      summary(class: "cursor-pointer text-blue-500 text-xs list-none") { plain "展開 ▾" }
      div(class: "mt-2 text-left text-[11px] text-gray-500 space-y-0.5 whitespace-nowrap") do
        p { plain "Long Bid/Ask #{fmt_price(long_leg[:bid])}/#{fmt_price(long_leg[:ask])}　OI #{fmt_int(long_leg[:oi])}" }
        p { plain "Long 內在/外在 #{fmt_price(long_leg[:intrinsic])}/#{fmt_price(long_leg[:extrinsic])}" }
        p { plain "Short Bid/Ask #{fmt_price(short_leg[:bid])}/#{fmt_price(short_leg[:ask])}　Theo #{fmt_price(short_leg[:theoretical_price])}" }
        p { plain "Short Moneyness #{fmt_pct(short_leg[:moneyness])}" }
        p do
          plain "Gamma #{fmt_decimal(short_leg[:gamma], 4)}"
          if short_leg[:gamma].to_f > 0.20
            span(class: "text-orange-600") { plain " ⚠️" }
          end
        end
        p { plain "Theta #{fmt_decimal(short_leg[:theta], 4)}　Vega #{fmt_decimal(short_leg[:vega], 4)}" }
        p { plain "IV #{fmt_pct(short_leg[:iv])}　ITM Prob #{fmt_pct(short_leg[:itm_probability])}" }
        p { plain "Vol #{fmt_int(short_leg[:vol])}　OI #{fmt_int(short_leg[:oi])}　Vol/OI #{fmt_decimal(short_leg[:vol_oi_ratio], 3)}　OI Chg #{fmt_int(short_leg[:oi_change])}" }
        p { plain "MaxProfit(未收租) #{fmt_price(combo[:max_profit_no_sc])}　收租率(未年化) #{fmt_pmcc_pct(combo[:premium_yield])}" }
      end
    end
  end

  def pmcc_signed_color(val)
    return "" if val.nil?
    val.to_f >= 0 ? "text-green-600" : "text-red-600"
  end

  # premium_yield／premium_yield_ann 在 PmccRankingService 已經是「百分比數字」
  # （7.88 代表 7.88%，不是 0.0788），跟 fmt_pct（吃小數再 ×100）用途不同，
  # 不能共用同一支 formatter，否則會被再乘一次 100 變成離譜的數字。
  def fmt_pmcc_pct(val)
    return "—" if val.nil?
    sprintf("%.1f%%", val.to_f)
  end

  # ── PMCC v3 §9.2: 教育說明區（無資料也要獨立渲染，不得 500） ──────────────────
  #
  # CSS Token 精確移植 lesson9 :root（規格明文禁止重新設計），用 Tailwind
  # arbitrary values 表達，不建立獨立 scoped CSS 檔。

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
      p(class: "text-[11px] text-[#7A6555] mt-2") { plain "本表抓最近三到期日，天然落在 6–50 天。" }
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
          render_pmcc_bullet(3, "短期虛值 SC：最近三到期日、Delta 0.20–0.35、收租 $#{fmt_int(short_premium.round)}")
          render_pmcc_bullet(4, "資金比例 #{capital_ratio ? fmt_pmcc_pct(capital_ratio) : '—'}")
        else
          render_pmcc_bullet(1, "買100股成本 —")
          render_pmcc_bullet(2, "LEAPS 成本 —")
          render_pmcc_bullet(3, "短期虛值 SC：最近三到期日、Delta 0.20–0.35、收租 —")
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

  def render_loading_script
    csrf = helpers.form_authenticity_token rescue ""
    script do
      raw <<~JS.html_safe
        (function () {
          var form    = document.getElementById('leaps-form');
          var btn     = document.getElementById('leaps-submit-btn');
          var loading = document.getElementById('leaps-loading');
          if (!form || !btn || !loading) return;

          var inp = document.getElementById('leaps-symbol-input');
          var strikeInp = document.getElementById('leaps-strike-input');
          var strikeErr = document.getElementById('leaps-strike-error');

          if (inp) {
            inp.addEventListener('input', function () {
              this.value = this.value.toUpperCase();
              // Clear strike and error when symbol changes (snapshot no longer valid)
              if (strikeInp) strikeInp.value = '';
              if (strikeErr) { strikeErr.classList.add('hidden'); strikeErr.textContent = ''; }
            });
          }

          form.addEventListener('submit', function (e) {
            e.preventDefault();
            var symbol = inp ? inp.value.trim().toUpperCase() : '';
            if (!symbol) return;

            if (strikeErr) { strikeErr.classList.add('hidden'); strikeErr.textContent = ''; }
            var userStrike = strikeInp ? strikeInp.value.trim() : '';

            btn.disabled = true;
            btn.textContent = '查詢中…';
            btn.classList.add('opacity-50', 'cursor-not-allowed');
            loading.classList.remove('hidden');
            loading.classList.add('flex');

            var csrfToken = document.querySelector('meta[name="csrf-token"]');
            var token = csrfToken ? csrfToken.content : '#{csrf}';

            var strikeSuffix = userStrike ? '&user_strike=' + encodeURIComponent(userStrike) : '';

            var body = { symbol: symbol };
            if (userStrike) body.user_strike = userStrike;

            fetch('/leaps/analyze', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
              body: JSON.stringify(body)
            })
            .then(function (r) { return r.json(); })
            .then(function (data) {
              if (data.status === 'ready') {
                window.location.href = '/leaps?symbol=' + symbol + strikeSuffix;
                return;
              }
              if (data.status === 'cdp_offline') {
                window.location.href = '/leaps?symbol=' + symbol + '&job_status=cdp_offline' + strikeSuffix;
                return;
              }
              if (data.status === 'invalid_strike') {
                // Show inline error, re-enable form
                if (strikeErr) {
                  strikeErr.textContent = data.message || '履約價不在有效範圍，請重新輸入。';
                  strikeErr.classList.remove('hidden');
                }
                btn.disabled = false;
                btn.textContent = '查詢';
                btn.classList.remove('opacity-50', 'cursor-not-allowed');
                loading.classList.add('hidden');
                loading.classList.remove('flex');
                return;
              }
              var jobId = data.job_id;
              if (!jobId) {
                window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
                return;
              }
              var attempts = 0;
              var pollInterval = setInterval(function () {
                attempts++;
                if (attempts > 240) {
                  clearInterval(pollInterval);
                  window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
                  return;
                }
                fetch('/leaps/status?job_id=' + jobId)
                  .then(function (r) { return r.json(); })
                  .then(function (s) {
                    if (s.status === 'pending' || s.status === 'not_found') return;
                    clearInterval(pollInterval);
                    window.location.href = '/leaps?symbol=' + symbol + '&job_status=' + s.status + strikeSuffix;
                  }).catch(function () {});
              }, 2500);
            }).catch(function () {
              window.location.href = '/leaps?symbol=' + symbol + '&job_status=error' + strikeSuffix;
            });
          });
        })();
      JS
    end
  end

  # Phase I：匯出 PNG/PDF。事件委派（規格禁止 inline onclick）；
  # PDF 一律先轉 PNG 再嵌入（頁面含中文，jsPDF 文字模式需嵌 CJK 字型，圖片嵌入繞開豆腐字）。
  def render_export_script
    script do
      raw <<~JS.html_safe
        (function () {
          function timestamp() {
            var d = new Date();
            function p(n) { return String(n).padStart(2, '0'); }
            return '' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '_' + p(d.getHours()) + p(d.getMinutes());
          }

          var exporting = false;

          function exportPng(root, fname) {
            var bg = getComputedStyle(document.body).backgroundColor || '#ffffff';

            // 匯出前把所有 overflow:auto/scroll 容器暫時改為 visible，匯出後還原。
            // 必須無條件處理，不能只看 live DOM 有沒有實際溢出：html-to-image 的
            // clone 在 SVG foreignObject 內字體度量略有差異，live 無溢出的容器在
            // clone 裡可能溢出幾 px，就會把捲軸畫進輸出、蓋住最後一列（實測 NVTS）。
            var expanded = [];
            root.querySelectorAll('*').forEach(function (el) {
              var cs = getComputedStyle(el);
              if (/(auto|scroll)/.test(cs.overflow + cs.overflowX + cs.overflowY)) {
                expanded.push({ el: el, style: el.getAttribute('style') });
                el.style.overflow = 'visible';
                if (el.scrollHeight > el.clientHeight + 1) {
                  el.style.maxHeight = 'none';
                  el.style.height = 'auto';
                }
              }
            });
            // data-export-exclude 元素（字卡區等）暫時 display:none：html-to-image 的
            // filter 只是不畫內容，root 的量測高度仍會把它們算進去，展開中的字卡會在
            // 輸出底部留下一大段空白（實測 +2200px）。隱藏後畫布高度即為純資料內容。
            root.querySelectorAll('[data-export-exclude]').forEach(function (el) {
              expanded.push({ el: el, style: el.getAttribute('style') });
              el.style.display = 'none';
            });
            function restoreExpanded() {
              expanded.forEach(function (s) {
                if (s.style === null) s.el.removeAttribute('style');
                else s.el.setAttribute('style', s.style);
              });
            }

            return htmlToImage.toPng(root, {
              pixelRatio: 2,
              backgroundColor: bg,
              filter: function (node) {
                return !(node.nodeType === 1 && node.hasAttribute && node.hasAttribute('data-export-exclude'));
              }
            }).then(function (dataUrl) {
              var a = document.createElement('a');
              a.href = dataUrl;
              a.download = fname + '.png';
              document.body.appendChild(a);
              a.click();
              a.remove();
            }).finally(restoreExpanded);
          }

          document.addEventListener('click', function (e) {
            var btnEl = e.target.closest('[data-leaps-export]');
            if (!btnEl || btnEl.disabled || exporting) return;

            var kind = btnEl.getAttribute('data-leaps-export');
            if (kind === 'png' && typeof htmlToImage === 'undefined') { alert('匯出元件未載入，請重新整理頁面'); return; }
            if (kind === 'pdf' && typeof jspdf === 'undefined') { alert('PDF 元件未載入，請重新整理頁面'); return; }

            var root = document.getElementById('leaps-export-root');
            if (!root) return;

            var pngBtn = document.getElementById('leaps-export-png');
            var pdfBtn = document.getElementById('leaps-export-pdf');
            var origText = btnEl.textContent;
            exporting = true;
            [pngBtn, pdfBtn].forEach(function (b) { if (b) b.disabled = true; });
            btnEl.textContent = '匯出中…';

            var symEl  = document.getElementById('leaps-symbol-input');
            var symbol = (symEl && symEl.value ? symEl.value : 'UNKNOWN').toUpperCase();
            var fname  = 'leaps_' + symbol + '_' + timestamp();

            // Phase J：PNG 走既有 DOM 截圖路線（完全不動）；PDF 改走向量文字
            // 路線，直接從結構化資料繪製，不需要 DOM 截圖或 overflow/exclude 處理。
            var task = kind === 'png' ? exportPng(root, fname) : window.__leapsExportVectorPdf(fname);

            task.catch(function (err) {
              alert('匯出失敗：' + (err && err.message ? err.message : err));
            }).finally(function () {
              exporting = false;
              [pngBtn, pdfBtn].forEach(function (b) { if (b) b.disabled = false; });
              btnEl.textContent = origText;
            });
          });
        })();
      JS
    end
  end

  # Phase J（leaps-phase-j-vector-pdf-spec.md）：PDF 向量文字匯出。
  # 完全獨立於 PNG 路線——不截圖 DOM，直接從 #leaps-pdf-data 的結構化資料繪製。
  # 字型載入或 addFont 失敗時必須拋出中止匯出，不得 fallback 到 jsPDF 內建字型
  # （會產出滿頁豆腐字但「成功下載」），也不得 fallback 回舊的 PNG 嵌入路線。
  def render_vector_pdf_script
    script do
      raw <<~JS.html_safe
        (function () {
          var FONT_ALIAS     = 'NotoSansTC';
          var FONT_FILE      = 'NotoSansTC-Regular.ttf';
          var IPA_FONT_ALIAS = 'NotoSansIPA';
          var IPA_FONT_FILE  = 'NotoSans-Regular-ipa.ttf';

          // 通用字型載入：fetch → arrayBuffer → base64 → addFileToVFS/addFont，
          // 驗證 addFont 真的生效才算成功。任一字型失敗都必須中止匯出，不得
          // fallback 到 jsPDF 內建字型（豆腐字）——這條規則對主字型與 IPA
          // 字型一視同仁，IPA 字型是術語字卡音標顯示的必要條件，不是可選項。
          function loadFontFile(pdf, fontUrl, fontFile, fontAlias, label) {
            if (!fontUrl) return Promise.reject(new Error(label + '字型路徑未提供，無法產生向量 PDF'));
            return fetch(fontUrl).then(function (resp) {
              if (!resp.ok) throw new Error(label + '字型下載失敗（HTTP ' + resp.status + '），已中止匯出');
              return resp.arrayBuffer();
            }).then(function (buf) {
              var bytes = new Uint8Array(buf);
              var binary = '';
              var chunk = 0x8000;
              for (var i = 0; i < bytes.length; i += chunk) {
                binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
              }
              var base64 = btoa(binary);
              pdf.addFileToVFS(fontFile, base64);
              pdf.addFont(fontFile, fontAlias, 'normal');
              var list = pdf.getFontList();
              if (!list[fontAlias] || list[fontAlias].indexOf('normal') === -1) {
                throw new Error(label + '字型載入失敗（addFont 未生效），已中止匯出');
              }
            });
          }

          function loadFont(pdf, fontUrl, ipaFontUrl) {
            return loadFontFile(pdf, fontUrl, FONT_FILE, FONT_ALIAS, '主')
              .then(function () { return loadFontFile(pdf, ipaFontUrl, IPA_FONT_FILE, IPA_FONT_ALIAS, 'IPA 音標'); })
              .then(function () { pdf.setFont(FONT_ALIAS, 'normal'); });
          }

          // CJK 沒有空白字元，jsPDF 內建 splitTextToSize 依空白斷詞會讓整段中文
          // 衝出頁面右緣不換行——改用逐字寬度量測（getTextWidth）自行換行。
          function wrapCjk(pdf, text, maxWidth) {
            var lines = [];
            var current = '';
            for (var i = 0; i < text.length; i++) {
              var ch = text[i];
              var test = current + ch;
              if (current.length > 0 && pdf.getTextWidth(test) > maxWidth) {
                lines.push(current);
                current = ch;
              } else {
                current = test;
              }
            }
            if (current.length > 0) lines.push(current);
            return lines;
          }

          function hexToRgb(hex) {
            var h = hex.replace('#', '');
            return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
          }

          function pageBottom(pdf) { return pdf.internal.pageSize.getHeight() - 16; }

          function renderRecoGroup(pdf, group, margin, y, maxWidth) {
            if (!group) return y;
            var bottom = pageBottom(pdf);
            if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
            pdf.setFontSize(11);
            pdf.text(group.label, margin, y);
            y += 6.5;
            if (group.badge) {
              // 彩色徽章比照 HTML render_pick_badge（色塊背景+邊框+圓點+文字），
              // 用同一組 PDF_SIGNAL_HEX（跟排行表流動性欄位、Flow 方向欄同一色票）
              var b = group.badge;
              pdf.setFontSize(8.5);
              var badgeText = b.text + '   ' + b.delta_text;
              var textW = pdf.getTextWidth(badgeText);
              var padX = 3, boxH = 6.5, boxW = textW + padX * 2 + 4;
              pdf.setFillColor.apply(pdf, hexToRgb(b.color.bg));
              pdf.setDrawColor.apply(pdf, hexToRgb(b.color.border));
              pdf.roundedRect(margin, y - boxH + 1.8, boxW, boxH, 1, 1, 'FD');
              pdf.setFillColor.apply(pdf, hexToRgb(b.color.dot));
              pdf.circle(margin + padX + 1, y - boxH / 2 + 1.8, 1, 'F');
              pdf.setTextColor.apply(pdf, hexToRgb(b.color.text));
              pdf.text(badgeText, margin + padX + 4, y);
              pdf.setTextColor(0, 0, 0);
              y += 6;
            }
            pdf.setFontSize(8.5);
            var text = group.no_candidates ? '此天期區間目前沒有符合條件的候選。' : (group.reason || '');
            var paragraphs = text.split('\\n');
            for (var pi = 0; pi < paragraphs.length; pi++) {
              var lines = wrapCjk(pdf, paragraphs[pi], maxWidth);
              for (var li = 0; li < lines.length; li++) {
                if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
                pdf.text(lines[li], margin, y);
                y += 4;
              }
            }
            y += 3;
            return y;
          }

          // 卡片底色/邊框比照 HTML 版 leaps-concept-card／leaps-vocab-card
          // （奇數綠底 #dcfce7、偶數紫底 #ede9fe、橘框 #f97316，見 application.css）。
          var CARD_FILL_COLORS = ['#dcfce7', '#ede9fe'];
          var CARD_BORDER_COLOR = '#f97316';
          var CARD_TITLE_COLOR = '#111827';
          var CARD_BODY_COLOR = '#1f2937';

          // 量測卡片段落換行後的總高度，用來在畫底色框之前先算好框的高度。
          function measureWrappedLines(pdf, paragraphs, maxWidth) {
            var wrapped = [];
            var total = 0;
            for (var pi = 0; pi < paragraphs.length; pi++) {
              var lines = wrapCjk(pdf, paragraphs[pi], maxWidth);
              wrapped.push(lines);
              total += lines.length;
            }
            return { wrapped: wrapped, lineCount: total };
          }

          function renderConceptCards(pdf, cards, margin, y, maxWidth) {
            if (!cards || !cards.length) return y;
            var bottom = pageBottom(pdf);
            if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
            pdf.setFontSize(9);
            pdf.setTextColor(107, 114, 128);
            pdf.text('名詞解釋（以本次推薦合約的實際數值試算）', margin, y);
            pdf.setTextColor(0, 0, 0);
            y += 6;
            for (var ci = 0; ci < cards.length; ci++) {
              var card = cards[ci];
              pdf.setFontSize(8.5);
              var measured = measureWrappedLines(pdf, card.paragraphs, maxWidth - 6);
              var titleH = 5, lineH = 4;
              var cardH = titleH + measured.lineCount * lineH + 3;
              if (y - 4 + 5 + cardH + 3 > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }

              var innerX = margin + 3;
              var textY = y + 5;
              pdf.setFillColor.apply(pdf, hexToRgb(CARD_FILL_COLORS[ci % 2]));
              pdf.setDrawColor.apply(pdf, hexToRgb(CARD_BORDER_COLOR));
              pdf.setLineWidth(0.35);
              pdf.roundedRect(margin, y - 4, maxWidth, 5 + titleH + measured.lineCount * lineH + 3, 2, 2, 'FD');

              pdf.setFontSize(10.5);
              pdf.setTextColor.apply(pdf, hexToRgb(CARD_TITLE_COLOR));
              pdf.text(card.title, innerX, textY);
              textY += titleH;
              pdf.setFontSize(8.5);
              pdf.setTextColor.apply(pdf, hexToRgb(CARD_BODY_COLOR));
              for (var pi = 0; pi < measured.wrapped.length; pi++) {
                var lines = measured.wrapped[pi];
                for (var li = 0; li < lines.length; li++) {
                  pdf.text(lines[li], innerX, textY);
                  textY += lineH;
                }
              }
              pdf.setTextColor(0, 0, 0);
              y = textY + 4;
            }
            y += 2;
            return y;
          }

          function renderVocabCards(pdf, cards, margin, y, maxWidth) {
            if (!cards || !cards.length) return y;
            var bottom = pageBottom(pdf);
            if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
            pdf.setFontSize(13);
            pdf.text('術語字卡', margin, y);
            y += 4;
            pdf.setFontSize(8);
            pdf.setTextColor(156, 163, 175);
            pdf.text('（正反面內容攤平合併顯示）', margin, y);
            pdf.setTextColor(0, 0, 0);
            y += 6;
            var innerWidth = maxWidth - 6;
            for (var vi = 0; vi < cards.length; vi++) {
              var card = cards[vi];
              pdf.setFontSize(7.5);
              var hintLines = wrapCjk(pdf, card.hint, innerWidth);
              pdf.setFontSize(8);
              var backLines = wrapCjk(pdf, card.back, innerWidth);
              pdf.setFontSize(7.5);
              var exLines = wrapCjk(pdf, card.ex, innerWidth);
              var cardH = 4.2 + hintLines.length * 3.6 + backLines.length * 3.8 + exLines.length * 3.6 + 3;
              // 卡片可能整張跨頁面過長，這裡只確保「至少一行」不被切在頁尾。
              if (y - 4 + 5 + cardH > bottom && cardH <= bottom - margin) {
                pdf.addPage(); y = margin; bottom = pageBottom(pdf);
              } else if (y > bottom - 10) {
                pdf.addPage(); y = margin; bottom = pageBottom(pdf);
              }

              var innerX = margin + 3;
              pdf.setFillColor.apply(pdf, hexToRgb(CARD_FILL_COLORS[vi % 2]));
              pdf.setDrawColor.apply(pdf, hexToRgb(CARD_BORDER_COLOR));
              pdf.setLineWidth(0.35);
              pdf.roundedRect(margin, y - 4, maxWidth, 5 + cardH, 2, 2, 'FD');

              // 混合字型繪製同一行：英文/中文用嵌入的 Noto Sans TC 子集，
              // 音標用第二個嵌入字型 NotoSansIPA（Noto Sans 拉丁字型子集，
              // 涵蓋 Noto Sans TC 缺少的 ɪ/ɛ/ə/ʊ/ˈ/ː 等 IPA Extensions 符號）。
              // jsPDF 單次 pdf.text() 呼叫只能用單一字型，混合字型需要逐段
              // 呼叫 getTextWidth() 手動定位 x 座標分段畫。
              pdf.setFontSize(10);
              var vx = innerX;
              pdf.setFont(FONT_ALIAS, 'normal');
              pdf.setTextColor.apply(pdf, hexToRgb(CARD_TITLE_COLOR));
              var enSeg = card.en + '  ';
              pdf.text(enSeg, vx, y);
              vx += pdf.getTextWidth(enSeg);

              pdf.setFont(IPA_FONT_ALIAS, 'normal');
              var ipaSeg = card.ipa + '  ';
              pdf.text(ipaSeg, vx, y);
              vx += pdf.getTextWidth(ipaSeg);

              pdf.setFont(FONT_ALIAS, 'normal');
              pdf.text('— ' + card.zh, vx, y);
              y += 4.2;
              pdf.setFontSize(7.5);
              pdf.setTextColor(107, 114, 128);
              for (var hi = 0; hi < hintLines.length; hi++) {
                pdf.text(hintLines[hi], innerX, y);
                y += 3.6;
              }
              pdf.setTextColor.apply(pdf, hexToRgb(CARD_BODY_COLOR));
              pdf.setFontSize(8);
              for (var bi = 0; bi < backLines.length; bi++) {
                pdf.text(backLines[bi], innerX, y);
                y += 3.8;
              }
              pdf.setTextColor(107, 114, 128);
              pdf.setFontSize(7.5);
              for (var ei = 0; ei < exLines.length; ei++) {
                pdf.text(exLines[ei], innerX, y);
                y += 3.6;
              }
              pdf.setTextColor(0, 0, 0);
              y += 3 + 4;
            }
            return y;
          }

          function renderCandidatesTable(pdf, rows, margin, y) {
            var head = [['到期日','DTE','履約價','Delta','OI','Volume','流動性判斷','Bid','Ask','Mid',
                         'Spread%','內在價值','外在價值','外在佔比','Time Value%','IV','Vega','被指派機率']];
            var body = rows.map(function (r) {
              return [r.expiration_date, r.dte, r.strike, r.delta, r.oi, r.volume, r.liquidity,
                      r.bid, r.ask, r.mid, r.spread, r.intrinsic, r.extrinsic, r.extrinsic_pct,
                      r.time_value_pct, r.iv, r.vega, r.itm_prob];
            });
            var liqCol = 6;
            pdf.autoTable({
              head: head, body: body, startY: y,
              margin: { left: margin, right: margin },
              styles: { font: FONT_ALIAS, fontSize: 6.5, cellPadding: 1.2, textColor: [55, 65, 81] },
              headStyles: { font: FONT_ALIAS, fillColor: [243, 244, 246], textColor: [55, 65, 81], fontSize: 6.5 },
              didParseCell: function (hd) {
                if (hd.section === 'body' && hd.column.index === liqCol) {
                  var rgb = rows[hd.row.index].liquidity_rgb;
                  if (rgb) {
                    hd.cell.styles.fillColor = hexToRgb(rgb.bg);
                    hd.cell.styles.textColor = hexToRgb(rgb.text);
                  }
                }
              }
            });
            return pdf.lastAutoTable.finalY + 8;
          }

          function renderFlowTable(pdf, rows, margin, y, summary, highlights, maxWidth) {
            var bottom = pageBottom(pdf);
            if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
            pdf.setFontSize(11);
            pdf.text('Options Flow — 情緒參考，非排序依據', margin, y);
            if (summary) {
              // 右上角 Call/Put 總額（比照 HTML 頁面右上角同一塊資訊，Call 綠字／Put 紅字）
              pdf.setFontSize(9);
              var callText = 'Call ' + summary.call_total;
              var sep = '  ·  ';
              var putText = 'Put ' + summary.put_total;
              var totalWidth = pdf.getTextWidth(callText) + pdf.getTextWidth(sep) + pdf.getTextWidth(putText);
              var sx = margin + maxWidth - totalWidth;
              pdf.setTextColor.apply(pdf, hexToRgb(summary.call_color));
              pdf.text(callText, sx, y);
              sx += pdf.getTextWidth(callText);
              pdf.setTextColor(156, 163, 175);
              pdf.text(sep, sx, y);
              sx += pdf.getTextWidth(sep);
              pdf.setTextColor.apply(pdf, hexToRgb(summary.put_color));
              pdf.text(putText, sx, y);
              pdf.setTextColor(0, 0, 0);
            }
            y += 4.5;
            if (summary && summary.date) {
              pdf.setFontSize(8);
              pdf.setTextColor(107, 114, 128);
              pdf.text(summary.date + ' · 前 20 大成交（依 Premium 降序）', margin, y);
              pdf.setTextColor(0, 0, 0);
              y += 5;
            }
            if (highlights && highlights.length) {
              pdf.setFontSize(8.5);
              pdf.setTextColor(29, 78, 216);
              pdf.text('排行候選 × 今日 Flow 重疊', margin, y);
              y += 4;
              pdf.setFontSize(7.5);
              for (var hi = 0; hi < highlights.length; hi++) {
                if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
                var lines = wrapCjk(pdf, highlights[hi], maxWidth);
                for (var hli = 0; hli < lines.length; hli++) {
                  pdf.text(lines[hli], margin, y);
                  y += 3.6;
                }
              }
              pdf.setTextColor(0, 0, 0);
              y += 2;
            }
            var head = [['類型','履約價','到期日','DTE','Delta','Code','Size','Side','Premium','方向']];
            var body = rows.map(function (t) {
              return [t.type, t.strike, t.expires, t.dte, t.delta, t.code, t.size, t.side, t.premium, t.direction];
            });
            var dirCol = 9;
            pdf.autoTable({
              head: head, body: body, startY: y,
              margin: { left: margin, right: margin },
              styles: { font: FONT_ALIAS, fontSize: 7, cellPadding: 1.2 },
              headStyles: { font: FONT_ALIAS, fillColor: [243, 244, 246], textColor: [55, 65, 81], fontSize: 7 },
              didParseCell: function (hd) {
                if (hd.section === 'body' && hd.column.index === dirCol) {
                  var rgb = rows[hd.row.index].direction_rgb;
                  if (rgb) hd.cell.styles.textColor = hexToRgb(rgb.text);
                }
              }
            });
            return pdf.lastAutoTable.finalY + 8;
          }

          function buildVectorPdf(pdf, data) {
            var pageW = pdf.internal.pageSize.getWidth();
            var pageH = pdf.internal.pageSize.getHeight();
            var margin = 12;
            var y = margin;

            pdf.setFont(FONT_ALIAS, 'normal');
            pdf.setFontSize(16);
            pdf.text('LEAPS Call 候選排行 — ' + data.symbol, margin, y);
            y += 6;
            pdf.setFontSize(9);
            pdf.setTextColor(107, 114, 128);
            pdf.text('Delta 0.60–0.90 深度價內 Call · 依 OI 由高到低排序', margin, y);
            pdf.setTextColor(0, 0, 0);
            y += 8;

            if (data.recommendation) {
              y = renderRecoGroup(pdf, data.recommendation.near_term, margin, y, pageW - margin * 2);
              y = renderRecoGroup(pdf, data.recommendation.far_term, margin, y, pageW - margin * 2);
            }

            if (data.concept_cards && data.concept_cards.length) {
              if (y > pageH - 40) { pdf.addPage(); y = margin; }
              y = renderConceptCards(pdf, data.concept_cards, margin, y, pageW - margin * 2);
            }

            if (data.candidates && data.candidates.length) {
              if (y > pageH - 40) { pdf.addPage(); y = margin; }
              y = renderCandidatesTable(pdf, data.candidates, margin, y);
            }

            if (data.flow_rows && data.flow_rows.length) {
              if (y > pageH - 40) { pdf.addPage(); y = margin; }
              y = renderFlowTable(pdf, data.flow_rows, margin, y, data.flow_summary, data.flow_highlights, pageW - margin * 2);
            }

            if (data.vocab_cards && data.vocab_cards.length) {
              pdf.addPage(); y = margin; // 教學資源另起一頁，跟查詢結果本身分開
              y = renderVocabCards(pdf, data.vocab_cards, margin, y, pageW - margin * 2);
            }

            var pageCount = pdf.internal.getNumberOfPages();
            for (var p = 1; p <= pageCount; p++) {
              pdf.setPage(p);
              pdf.setFont(FONT_ALIAS, 'normal');
              pdf.setFontSize(7);
              pdf.setTextColor(156, 163, 175);
              pdf.text('僅供策略篩選參考，非投資建議，請自行評估。', margin, pageH - 6);
              pdf.setTextColor(0, 0, 0);
            }
          }

          window.__leapsExportVectorPdf = function (fname) {
            var root = document.getElementById('leaps-export-root');
            var fontUrl    = root ? root.getAttribute('data-pdf-font-url') : null;
            var ipaFontUrl = root ? root.getAttribute('data-pdf-ipa-font-url') : null;
            var dataEl = document.getElementById('leaps-pdf-data');

            var payload;
            try {
              payload = JSON.parse(dataEl ? dataEl.textContent : 'null');
            } catch (parseErr) {
              return Promise.reject(new Error('PDF 資料解析失敗，已中止匯出'));
            }
            if (!payload) return Promise.reject(new Error('找不到匯出資料，已中止匯出'));

            var pdf = new jspdf.jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });

            return loadFont(pdf, fontUrl, ipaFontUrl).then(function () {
              buildVectorPdf(pdf, payload);
              pdf.save(fname + '.pdf');
            });
          };
        })();
      JS
    end
  end

  # 術語字卡區：<details> 收合、深色卡面、rotateY 翻面、🔊 Web Speech 發音。
  # data-export-exclude：教學元素不入匯出畫面（與導覽/匯出按鈕同規則）。
  def render_vocab_cards
    details(class: "bg-white rounded-xl border border-gray-200 shadow-sm", data_export_exclude: "") do
      summary(class: "leaps-vocab-summary") { plain "📚 術語字卡（點擊翻面 · 🔊 聽發音）" }
      div(class: "px-4 pb-4") do
        div(class: "leaps-vocab-grid") do
          VOCAB_CARDS.each { |card| render_vocab_card(card) }
        end
      end
    end
  end

  def render_vocab_card(card)
    div(class: "leaps-vocab-card") do
      div(class: "leaps-vocab-inner") do
        div(class: "leaps-vocab-front") do
          button(class: "speak-btn", type: "button", data_term: card[:en],
                 aria_label: "朗讀 #{card[:en]}") { plain "🔊" }
          div(class: "leaps-vc-en")   { plain card[:en] }
          div(class: "leaps-vc-ipa")  { plain card[:ipa] }
          div(class: "leaps-vc-zh")   { plain card[:zh] }
          div(class: "leaps-vc-hint") { plain card[:hint] }
        end
        div(class: "leaps-vocab-back") do
          div(class: "leaps-vc-back-title") { plain "#{card[:en]} — #{card[:zh]}" }
          div(class: "leaps-vc-back-body")  { plain card[:back] }
          div(class: "leaps-vc-example")    { plain card[:ex] }
        end
      end
    end
  end

  # 欄位教學三層互動（leaps-column-tooltips-spec.md）。
  # LEAPS_COL_EXPLAIN 是文案唯一來源：hover tooltip、點擊單步 popover、多步 tour 共用。
  def render_tooltips_script
    script do
      raw <<~JS.html_safe
        (function () {
          var LEAPS_COL_EXPLAIN = {
            expiration:     { el: '#leaps-th-expiration',     title: '📅 Expiration',           desc: '合約到期日。LEAPS 慣例為一年以上，本表只列 364 天以上。', side: 'bottom' },
            dte:            { el: '#leaps-th-dte',            title: '⏱ Days to Expiration',    desc: '距到期天數。364–550 近天期、550+ 遠天期；越長時間緩衝越大，Vega 曝險也越高。', side: 'bottom' },
            strike:         { el: '#leaps-th-strike',         title: '🎯 Strike',               desc: '約定買入股價。深價內的 Call 行為越接近持有正股。', side: 'bottom' },
            delta:          { el: '#leaps-th-delta',          title: '⚡ Delta',                 desc: '股價每動 $1 權利金的理論變化。本表篩 0.60–0.90；越接近 1 越像股票替代品，槓桿越低但越穩。', side: 'bottom' },
            oi:             { el: '#leaps-th-oi',             title: '🔓 Open Interest',        desc: '未平倉合約數，本表排序主鍵。OI 高流動性通常較好；只在盤後更新。', side: 'bottom' },
            volume:         { el: '#leaps-th-volume',         title: '📊 Volume',               desc: '當日成交量（即時）。OI 高但 Volume 長期為零，進出仍可能困難。', side: 'bottom' },
            liquidity:      { el: '#leaps-th-liquidity',      title: '🚦 流動性判斷',            desc: '依本次查詢候選的 OI 三分位相對排名（充足/普通/偏低），非固定門檻；「⚠ 近期無成交」由 Vol/OI 比率判斷。', side: 'bottom' },
            bid:            { el: '#leaps-th-bid',            title: '⬇️ Bid',                  desc: '市場最高買價（賣出時的底價參考）。', side: 'bottom' },
            ask:            { el: '#leaps-th-ask',            title: '⬆️ Ask',                  desc: '市場最低賣價（買入時的天花板參考）。', side: 'bottom' },
            mid:            { el: '#leaps-th-mid',            title: '⚖️ Mid',                  desc: '(Bid+Ask)/2，掛限價單參考價。本系統衍生欄位一律以 Mid 為權利金基準，不用可能過時的最後成交價。', side: 'bottom' },
            spread:         { el: '#leaps-th-spread',         title: '↔️ Spread%',              desc: '(Ask−Bid)/Mid，一次進出的滑價成本。深價內常偏寬，>10% 要注意。', side: 'bottom' },
            intrinsic:      { el: '#leaps-th-intrinsic',      title: '💎 Intrinsic Value',      desc: 'max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不流失。', side: 'bottom' },
            extrinsic:      { el: '#leaps-th-extrinsic',      title: '🎈 Extrinsic Value',      desc: 'Mid−內在價值，時間＋波動率溢價（保險費），隨時間與 IV 回落流失。', side: 'bottom' },
            extrinsic_pct:  { el: '#leaps-th-extrinsic_pct',  title: '🧮 外在佔比',              desc: '外在÷Mid，「權利金裡幾 % 是保險費」。深 ITM LEAPS 核心指標：越低越接近持股替代，高 IV 環境尤其要壓低。', side: 'bottom' },
            time_value_pct: { el: '#leaps-th-time_value_pct', title: '📐 Time Value%',          desc: '外在÷股價，「相對直接持股多付幾 % 溢價」。與外在佔比分母不同，回答不同問題。', side: 'bottom' },
            iv:             { el: '#leaps-th-iv',             title: '🌊 Implied Volatility',   desc: '該檔位隱含波動率。IV 越高權利金越貴；高 IV 買 LEAPS 要留意回落侵蝕（搭配 Vega）。', side: 'bottom' },
            vega:           { el: '#leaps-th-vega',           title: '🌀 Vega',                 desc: 'IV 每變 1% 權利金的理論變化。DTE 越長 Vega 越大；IV Crush 風險量化：IV 回落 10% ≈ 損失 Vega×10。', side: 'bottom' },
            itm_prob:       { el: '#leaps-th-itm_prob',       title: '🎲 ITM Probability',      desc: 'Barchart 估到期價內機率。買方視角＝到期仍有內在價值的機率，與 Delta 相關但獨立模型計算。', side: 'bottom' },
            f_type:         { el: '#leaps-th-f_type',         title: '🏷 Type',                 desc: 'Call（買權）或 Put（賣權）。搭配 Side 與方向欄一起判讀該筆大單的多空含義。', side: 'bottom' },
            f_strike:       { el: '#leaps-th-f_strike',       title: '🎯 Strike',               desc: '該筆成交合約的履約價。', side: 'bottom' },
            f_expiration:   { el: '#leaps-th-f_expiration',   title: '📅 Expiration',           desc: '該筆成交合約的到期日。本面板不限 LEAPS，任何到期日都會入榜。', side: 'bottom' },
            f_dte:          { el: '#leaps-th-f_dte',          title: '⏱ DTE',                   desc: '距到期天數。與排行表的 364 天門檻無關，這裡看的是當天市場在哪些天期活動。', side: 'bottom' },
            f_delta:        { el: '#leaps-th-f_delta',        title: '⚡ Delta',                 desc: '正值=Call、負值=Put；絕對值越大越深價內。', side: 'bottom' },
            f_code:         { el: '#leaps-th-f_code',         title: '🏳 Code',                 desc: '交易所成交代碼。標準單腿代碼可信；AUTO／多腿類（SLAN、MLET、ISOI 等）標記普遍缺失，判讀需保守。', side: 'bottom' },
            f_size:         { el: '#leaps-th-f_size',         title: '📦 Size',                 desc: '該筆成交口數（1 口 = 100 股）。', side: 'bottom' },
            f_side:         { el: '#leaps-th-f_side',         title: '↕️ Side',                 desc: '成交價位置：靠 bid=賣方主動（偏空）、靠 ask=買方主動（偏多）、mid=中性。', side: 'bottom' },
            f_premium:      { el: '#leaps-th-f_premium',      title: '💰 Premium',              desc: '該筆成交的權利金總額。本面板依 Premium 降序取前 20 筆。', side: 'bottom' },
            f_direction:    { el: '#leaps-th-f_direction',    title: '🧭 方向',                  desc: '綜合 Type／Side／Code 的看多/看空/中性判讀。情緒參考，不參與排行排序。', side: 'bottom' }
          };
          var TOUR_ORDER = ['expiration','dte','strike','delta','oi','volume','liquidity','bid','ask','mid','spread',
                            'intrinsic','extrinsic','extrinsic_pct','time_value_pct','iv','vega','itm_prob',
                            'f_type','f_strike','f_expiration','f_dte','f_delta','f_code','f_size','f_side','f_premium','f_direction'];

          /* hover tooltip 引擎（document 委派 + 單一 fixed 元素，掛 body、export root 之外） */
          var tip = document.createElement('div');
          tip.id = 'leaps-col-tip';
          tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
          document.body.appendChild(tip);
          var tT = tip.querySelector('.tip-t'), tB = tip.querySelector('.tip-b');
          function posTip(e) {
            var x = e.clientX + 14, y = e.clientY + 12,
                w = tip.offsetWidth || 280, h = tip.offsetHeight || 100;
            if (x + w > window.innerWidth - 10)  x = e.clientX - w - 10;
            if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
            tip.style.left = x + 'px'; tip.style.top = y + 'px';
          }
          document.addEventListener('mouseover', function (e) {
            var el = e.target.closest('[data-tip-key]');
            if (el) {
              var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
              if (!d) return;
              tT.textContent = d.title; tB.textContent = d.desc;
              tip.style.opacity = '1'; posTip(e);
            } else { tip.style.opacity = '0'; }
          });
          document.addEventListener('mousemove', function (e) {
            if (tip.style.opacity !== '0') posTip(e);
          });
          document.addEventListener('mouseout', function (e) {
            if (!e.target.closest('[data-tip-key]')) tip.style.opacity = '0';
          });

          /* 術語字卡：speechSynthesis 不支援時隱藏全部 🔊（降級，不報錯） */
          if (!('speechSynthesis' in window)) {
            document.querySelectorAll('.leaps-vocab-card .speak-btn').forEach(function (b) { b.style.display = 'none'; });
          }

          /* 點擊 → 單步聚光 popover；導覽按鈕 → 28 步 tour（同一份文案 map）；
             字卡 → 翻面；🔊 → 朗讀不翻面（第 8 課 inline onclick 改為委派） */
          function drv() { return window.driver && window.driver.js && window.driver.js.driver; }
          document.addEventListener('click', function (e) {
            var spk = e.target.closest('.leaps-vocab-card .speak-btn');
            if (spk) {
              e.stopPropagation();
              if (!('speechSynthesis' in window)) return;
              if (speechSynthesis.speaking) speechSynthesis.cancel();
              var utt = new SpeechSynthesisUtterance(spk.dataset.term);
              utt.lang = 'en-US'; utt.rate = 0.85; utt.pitch = 1.0;
              spk.classList.add('speaking');
              utt.onend = function () { spk.classList.remove('speaking'); };
              utt.onerror = function () { spk.classList.remove('speaking'); };
              speechSynthesis.speak(utt);
              return;
            }
            var vcard = e.target.closest('.leaps-vocab-card');
            if (vcard) { vcard.classList.toggle('flipped'); return; }
            var el = e.target.closest('[data-tip-key]');
            if (el && drv()) {
              var d = LEAPS_COL_EXPLAIN[el.dataset.tipKey];
              if (!d) return;
              tip.style.opacity = '0';
              drv()({ animate: true, allowClose: true, overlayOpacity: 0.35,
                      steps: [{ element: d.el, popover: { title: d.title, description: d.desc, side: d.side, align: 'center' } }] }).drive();
              return;
            }
            var btn = e.target.closest('#leaps-tour-btn');
            if (btn && !btn.disabled && drv()) {
              var steps = TOUR_ORDER
                .filter(function (k) { return document.querySelector(LEAPS_COL_EXPLAIN[k].el); })
                .map(function (k) {
                  var d = LEAPS_COL_EXPLAIN[k];
                  return { element: d.el, popover: { title: d.title, description: d.desc, side: d.side, align: 'center' } };
                });
              if (steps.length) {
                drv()({ animate: true, allowClose: true, overlayOpacity: 0.4, showProgress: true, steps: steps }).drive();
              }
            }
          });
        })();
      JS
    end
  end

  # ── Partial error helpers ──────────────────────────────────────────────────

  def partial_error_strike
    return @_partial_error_strike if defined?(@_partial_error_strike)
    @_partial_error_strike = begin
      return nil unless @scrape_status == :partial_error
      msg = @scrape_errors.first.to_s
      m = msg.match(/Strike\s+(\d+(?:\.\d+)?)/)
      m ? m[1].to_f : nil
    end
  end

  def recommendation_strikes
    return [] unless @recommendation
    [
      @recommendation.dig(:near_term, :pick, :strike),
      @recommendation.dig(:far_term, :pick, :strike)
    ].compact
  end

  def fmt_strike_short(val)
    f = val.to_f
    f == f.to_i ? f.to_i.to_s : f.to_s
  end

  # ── 表格點表頭排序（LEAPS 排行表 + PMCC 表共用同一套 JS，見 render_sortable_table_script）──

  # 每個 key 對應 TABLE_COL_KEYS 同名欄位，供前端 JS 依 data-sort-key 做數值排序。
  # liquidity 不是天然數值，借用 LeapsRecommendationService::TIER_ORDER 轉成排序用等第。
  def leaps_row_sort_json(row, tier)
    {
      dte:            row[:dte],
      strike:         row[:strike]&.to_f,
      delta:          row[:delta]&.to_f,
      oi:             row[:open_interest],
      volume:         row[:volume],
      liquidity:      LeapsRecommendationService::TIER_ORDER[tier.to_s] || 0,
      bid:            row[:bid]&.to_f,
      ask:            row[:ask]&.to_f,
      mid:            row[:mid]&.to_f,
      spread:         row[:bid_ask_spread_pct]&.to_f,
      intrinsic:      row[:intrinsic_value]&.to_f,
      extrinsic:      row[:extrinsic_value]&.to_f,
      extrinsic_pct:  row[:extrinsic_pct]&.to_f,
      time_value_pct: row[:time_value_pct]&.to_f,
      iv:             row[:iv]&.to_f,
      vega:           row[:vega]&.to_f,
      itm_prob:       row[:itm_probability]&.to_f
    }.to_json
  end

  # 每個 key 對應 PMCC_TABLE_COL_KEYS 同名欄位。passes（Golden Rule）借用 1/0 排序，
  # 讓使用者也能點「Golden Rule」欄把通過的組合集中在最上面或最下面。
  def pmcc_combo_sort_json(combo)
    long_leg  = combo[:long_leg]
    short_leg = combo[:short_leg]
    {
      kl:          long_leg[:strike]&.to_f,
      pl:          long_leg[:mid]&.to_f,
      long_dte:    long_leg[:dte],
      long_delta:  long_leg[:delta]&.to_f,
      ks:          short_leg[:strike]&.to_f,
      ps:          short_leg[:mid]&.to_f,
      short_delta: short_leg[:delta]&.to_f,
      spread:      combo[:spread]&.to_f,
      net_debit:   combo[:net_debit]&.to_f,
      max_profit:  combo[:max_profit]&.to_f,
      yield_ann:   combo[:premium_yield_ann]&.to_f,
      passes:      combo[:passes_golden_rule] ? 1 : 0
    }.to_json
  end

  # ── Formatters ──────────────────────────────────────────────────────────────

  def fmt_int(val)
    return "—" if val.nil?
    n = val.to_i
    n.abs >= 1_000 ? sprintf("%d", n).reverse.scan(/\d{1,3}/).join(",").reverse : n.to_s
  end

  def fmt_price(val)
    return "—" if val.nil?
    sprintf("%.2f", val.to_f)
  end

  def fmt_decimal(val, digits)
    return "—" if val.nil?
    sprintf("%.#{digits}f", val.to_f)
  end

  def fmt_pct(val)
    return "—" if val.nil?
    sprintf("%.1f%%", val.to_f * 100)
  end

  def fmt_premium(val)
    return "—" if val.nil?
    n = val.to_i
    if n >= 1_000_000
      sprintf("$%.1fM", n / 1_000_000.0)
    elsif n >= 1_000
      sprintf("$%.0fK", n / 1_000.0)
    else
      sprintf("$%d", n)
    end
  end
end
