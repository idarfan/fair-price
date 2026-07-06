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

  TABLE_RIGHT_ALIGN_COLS = (
    %w[DTE Delta OI Volume Bid Ask Mid IV Vega] +
    ["履約價", "Spread%", "內在價值", "外在價值", "外在佔比", "Time Value%", "被指派機率"]
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

  def initialize(symbol: nil, candidates: [], recommendation: nil, flow_panel: nil, scrape_status: nil, scrape_errors: [], user_strike: nil)
    @symbol         = symbol
    @candidates     = Array(candidates)
    @recommendation = recommendation
    @flow_panel     = flow_panel
    @scrape_status  = scrape_status
    @scrape_errors  = Array(scrape_errors)
    @user_strike    = user_strike
  end

  def view_template
    div(id: "leaps-export-root", class: "space-y-6") do
      render_header
      render_search_form
      render_status_bar if @scrape_status
      if @candidates.any?
        render_recommendation if @recommendation
        render_ranking_table
        render_flow_panel if @flow_panel
      end
      render_vocab_cards
    end
    render_loading_script
    render_export_script
    render_tooltips_script
  end

  private

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
        table(class: "w-full text-xs text-gray-700") do
          thead(class: "bg-gray-50 text-gray-500 text-xs") do
            tr do
              TABLE_COLS.each_with_index do |col, idx|
                key = TABLE_COL_KEYS[idx]
                th(id: "leaps-th-#{key}", data_tip_key: key,
                   class: "px-3 py-2 text-center font-medium whitespace-nowrap") { plain col }
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

    tr(class: "border-t border-gray-100 hover:bg-purple-200 #{i.odd? ? 'bg-gray-50/50' : ''}") do
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

          document.addEventListener('click', function (e) {
            var btnEl = e.target.closest('[data-leaps-export]');
            if (!btnEl || btnEl.disabled || exporting) return;
            if (typeof htmlToImage === 'undefined') { alert('匯出元件未載入，請重新整理頁面'); return; }

            var kind = btnEl.getAttribute('data-leaps-export');
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
            // 背景色取 body 實際計算值，確保輸出不是透明底
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

            htmlToImage.toPng(root, {
              pixelRatio: 2,
              backgroundColor: bg,
              filter: function (node) {
                return !(node.nodeType === 1 && node.hasAttribute && node.hasAttribute('data-export-exclude'));
              }
            }).then(function (dataUrl) {
              if (kind === 'png') {
                var a = document.createElement('a');
                a.href = dataUrl;
                a.download = fname + '.png';
                document.body.appendChild(a);
                a.click();
                a.remove();
                return;
              }
              // PDF：載入 PNG 取得實際尺寸，開自訂尺寸單頁（長條式，不切 A4 避免腰斬表格列）
              return new Promise(function (resolve, reject) {
                var img = new Image();
                img.onload = function () {
                  try {
                    var w = img.naturalWidth, h = img.naturalHeight;
                    var pdf = new jspdf.jsPDF({
                      orientation: w > h ? 'landscape' : 'portrait',
                      unit: 'px',
                      format: [w, h],
                      hotfixes: ['px_scaling']
                    });
                    pdf.addImage(dataUrl, 'PNG', 0, 0, w, h, undefined, 'FAST');
                    pdf.save(fname + '.pdf');
                    resolve();
                  } catch (err) { reject(err); }
                };
                img.onerror = reject;
                img.src = dataUrl;
              });
            }).catch(function (err) {
              alert('匯出失敗：' + (err && err.message ? err.message : err));
            }).finally(function () {
              restoreExpanded();
              exporting = false;
              [pngBtn, pdfBtn].forEach(function (b) { if (b) b.disabled = false; });
              btnEl.textContent = origText;
            });
          });
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
