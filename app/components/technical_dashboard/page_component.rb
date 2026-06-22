# frozen_string_literal: true

class TechnicalDashboard::PageComponent < ApplicationComponent
  SCORE_META = {
    bullish:  { label: "偏多",   icon: "▲", color: "green" },
    bearish:  { label: "偏空",   icon: "▼", color: "red" },
    neutral:  { label: "中性",   icon: "—", color: "gray" },
    watching: { label: "觀察中", icon: "👁", color: "yellow" }
  }.freeze

  SIGNAL_DOT = {
    bullish:  "bg-green-400",
    bearish:  "bg-red-400",
    neutral:  "bg-gray-400",
    watching: "bg-yellow-400"
  }.freeze

  DIV_META = {
    warning:      { bg: "bg-orange-50", border: "border-orange-300", icon: "⚠️", text: "text-orange-800" },
    caution:      { bg: "bg-yellow-50", border: "border-yellow-300", icon: "💡", text: "text-yellow-800" },
    confirm_bull: { bg: "bg-green-50",  border: "border-green-300",  icon: "✅", text: "text-green-800" },
    confirm_bear: { bg: "bg-red-50",    border: "border-red-300",    icon: "🔴", text: "text-red-800" }
  }.freeze

  TECH_GRADIENT = [
    [0.00, [239, 68,  68]],
    [0.25, [248, 113, 113]],
    [0.50, [156, 163, 175]],
    [0.75, [129, 140, 248]],
    [1.00, [59,  130, 246]],
  ].freeze

  ANALYST_GRADIENT = [
    [0.00, [239, 68,  68]],
    [0.25, [249, 115, 22]],
    [0.50, [234, 179,  8]],
    [0.75, [132, 204, 22]],
    [1.00, [34,  197, 94]],
  ].freeze

  def initialize(symbol: nil, date: Date.today, result: nil, scrape_status: nil, scrape_errors: [], recent_symbols: [])
    @symbol        = symbol
    @date          = date
    @result        = result
    @scrape_status = scrape_status
    @scrape_errors    = Array(scrape_errors)
    @recent_symbols   = Array(recent_symbols)
  end

  def view_template
    div(class: "space-y-6") do
      render_header
      render_search_form
      render_recent_symbols unless @recent_symbols.empty?
      render_status_bar if @scrape_status
      if @result
        render_score_row
        render_data_detail
        render_flow_detail
        render_divergences
      end
    end
    render_loading_script
  end

  private

  # ---------------------------------------------------------------------------
  # Header
  # ---------------------------------------------------------------------------
  def render_header
    div(class: "flex items-center justify-between") do
      div do
        h1(class: "text-xl font-bold text-gray-900") { plain "三維度判斷儀表板" }
        p(class: "text-sm text-gray-500 mt-0.5") { plain "技術面 · 基本面 · Options Flow — 三個獨立訊號並列分析" }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Search form
  # ---------------------------------------------------------------------------
  def render_search_form
    form(
      id:     "td-form",
      action: "/technical_dashboard",
      method: "get",
      class:  "flex items-center gap-3"
    ) do
      input(
        id:          "td-symbol-input",
        type:        "text",
        name:        "symbol",
        value:       @symbol.to_s,
        placeholder: "輸入股票代號，例如 MU",
        maxlength:   "10",
        class:       "w-48 px-4 py-2 rounded-lg border border-gray-300 text-sm font-mono uppercase " \
                     "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
      )
      input(
        id:    "td-date-input",
        type:  "date",
        name:  "date",
        value: @date.to_s,
        class: "px-3 py-2 rounded-lg border border-gray-300 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
      )
      button(
        id:   "td-submit-btn",
        type: "submit",
        class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg " \
               "hover:bg-blue-700 transition-colors"
      ) { plain "分析" }
      div(
        id:    "td-loading",
        class: "hidden items-center gap-2 text-sm text-gray-500"
      ) do
        div(class: "w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin")
        plain "抓取資料中，請稍候…（約 20-30 秒）"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Recent query history chips
  # ---------------------------------------------------------------------------
  def render_recent_symbols
    div(class: "flex items-center gap-2 flex-wrap") do
      span(class: "text-xs text-gray-400 shrink-0") { plain "近期查詢：" }
      @recent_symbols.each do |sym|
        a(
          href:  "/technical_dashboard?symbol=#{sym}",
          class: "px-2.5 py-0.5 rounded-full text-xs font-mono border "                  "#{sym == @symbol ? 'bg-blue-100 border-blue-400 text-blue-700 font-bold' : 'bg-white border-gray-200 text-gray-600 hover:border-blue-300 hover:text-blue-600'}"
        ) { plain sym }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Status bar (session expired / error / cached)
  # ---------------------------------------------------------------------------
  def render_status_bar
    case @scrape_status
    when :no_data
      render_alert(
        bg:    "bg-gray-50 border-gray-200",
        icon:  "📭",
        color: "text-gray-600",
        title: "#{@date} 尚無資料",
        body:  "該日期資料未曾抓取，請改選今天或已有資料的日期。"
      )
    when :session_expired
      render_alert(
        bg:    "bg-amber-50 border-amber-200",
        icon:  "🔑",
        color: "text-amber-800",
        title: "Barchart 登入已過期",
        body:  "請在 Chrome 手動登入 Barchart，再回來重試。"
      )
    when :error
      render_alert(
        bg:    "bg-red-50 border-red-200",
        icon:  "❌",
        color: "text-red-800",
        title: "抓取失敗",
        body:  @scrape_errors.join("；")
      )
    when :cached
      div(class: "flex items-center gap-1.5 text-xs text-gray-400") do
        span { plain "⚡" }
        plain "使用 1 小時內快取資料"
        if @result&.[](:fetched_at)
          plain "（#{@date} #{@result[:fetched_at].strftime("%H:%M:%S")}）"
        end
      end
    when :fetched
      unless @scrape_errors.empty?
        render_alert(
          bg:    "bg-yellow-50 border-yellow-200",
          icon:  "⚠️",
          color: "text-yellow-800",
          title: "部分資料抓取失敗",
          body:  @scrape_errors.join("；")
        )
      end
    end
  end

  def render_alert(bg:, icon:, color:, title:, body:)
    div(class: "flex gap-3 px-4 py-3 rounded-lg border #{bg}") do
      span(class: "text-lg leading-none") { plain icon }
      div do
        p(class: "font-semibold text-sm #{color}") { plain title }
        p(class: "text-sm #{color} opacity-80 mt-0.5") { plain body } unless body.blank?
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Three score cards
  # ---------------------------------------------------------------------------
  def render_score_row
    tech = @result[:technical]
    fund = @result[:fundamental]
    flow = @result[:options_flow]

    div(class: "grid grid-cols-3 gap-4") do
      render_score_card(
        title:    "技術面",
        subtitle: "MA · ADX · Stochastic",
        data:     tech,
        gauge_t:  technical_gauge_t(tech),
        palette:  :tech
      )
      render_score_card(
        title:    "基本面",
        subtitle: "分析師評級 · EPS · P/E",
        data:     fund,
        gauge_t:  fundamental_gauge_t(fund),
        palette:  :analyst
      )
      render_score_card(
        title:    "Options Flow",
        subtitle: "C/P比率 · 主動買 · 大單分析",
        data:     flow,
        gauge_t:  options_flow_gauge_t(flow),
        palette:  :tech
      )
    end
  end

  def technical_gauge_t(data)
    return 0.5 if data[:missing]
    pts = (data[:points] || 0).clamp(-8, 8)
    (pts + 8.0) / 16.0
  end

  def fundamental_gauge_t(data)
    return 0.5 if data[:missing] || data[:score] == :watching
    pts = (data[:points] || 0).clamp(-4, 4)
    (pts + 4.0) / 8.0
  end

  def options_flow_gauge_t(data)
    return 0.5 if data[:missing]
    pts = (data[:points] || 0).clamp(-5, 5)
    (pts + 5.0) / 10.0
  end

  def render_score_card(title:, subtitle:, data:, gauge_t:, palette: :tech)
    score = data[:score]
    meta  = SCORE_META[score]
    color = meta[:color]
    border_class = "border-#{color}-500"
    text_class   = "text-#{color}-400"
    bg_class     = "bg-#{color}-500/10"

    # Signal counts
    sigs   = Array(data[:signals])
    n_bear = sigs.count { |s| s[:sentiment] == :bearish }
    n_neu  = sigs.count { |s| s[:sentiment] == :neutral }
    n_bull = sigs.count { |s| s[:sentiment] == :bullish }

    div(class: "rounded-xl border-2 bg-white shadow-sm p-4 space-y-3 #{border_class}") do
      # Header row
      div(class: "flex items-center justify-between") do
        div do
          p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider") { plain title }
          p(class: "text-xs text-gray-600 mt-0.5") { plain subtitle }
        end
        div(class: "text-xs font-bold px-2 py-0.5 rounded-full #{bg_class} #{text_class}") do
          plain meta[:label]
        end
      end

      # Gauge SVG
      raw(gauge_svg(t: gauge_t, missing: data[:missing], label: meta[:label], palette: palette))

      # Signal counts
      unless data[:missing]
        div(class: "flex justify-around text-center border-t border-gray-800 pt-2") do
          div do
            p(class: "text-lg font-bold text-red-400") { plain n_bear.to_s }
            p(class: "text-xs text-gray-500") { plain "空" }
          end
          div do
            p(class: "text-lg font-bold text-gray-400") { plain n_neu.to_s }
            p(class: "text-xs text-gray-500") { plain "中性" }
          end
          div do
            p(class: "text-lg font-bold text-green-400") { plain n_bull.to_s }
            p(class: "text-xs text-gray-500") { plain "多" }
          end
        end
      end

      # Key signals (max 3)
      unless data[:missing] || sigs.empty?
        div(class: "space-y-1") do
          sigs.first(3).each do |sig|
            dot = SIGNAL_DOT[sig[:sentiment]] || "bg-gray-400"
            div(class: "flex items-start gap-1.5") do
              span(class: "w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0 #{dot}")
              span(class: "text-xs text-gray-600 leading-snug") { plain sig[:text] }
            end
          end
        end
      end
    end
  end

  def gauge_color(t, stops)
    t = t.clamp(0.0, 1.0)
    lo_i = (stops.rindex { |t0, _| t0 <= t } || 0)
    hi_i = [lo_i + 1, stops.length - 1].min
    lo_t, lo_c = stops[lo_i]
    hi_t, hi_c = stops[hi_i]
    f = hi_t > lo_t ? (t - lo_t).to_f / (hi_t - lo_t) : 0.0
    r = (lo_c[0] + f * (hi_c[0] - lo_c[0])).round
    g = (lo_c[1] + f * (hi_c[1] - lo_c[1])).round
    b = (lo_c[2] + f * (hi_c[2] - lo_c[2])).round
    "rgb(#{r},#{g},#{b})"
  end

  def gauge_svg(t:, label:, missing: false, palette: :tech)
    t     = missing ? 0.5 : t.clamp(0.0, 1.0)
    stops = palette == :analyst ? ANALYST_GRADIENT : TECH_GRADIENT
    n     = 40

    segs = (0...n).map do |i|
      t0 = i.to_f / n
      t1 = (i + 1).to_f / n
      theta0 = Math::PI * (1.0 - t0)
      theta1 = Math::PI * (1.0 - t1)
      x0 = (100 + 80 * Math.cos(theta0)).round(3)
      y0 = (100 - 80 * Math.sin(theta0)).round(3)
      x1 = (100 + 80 * Math.cos(theta1)).round(3)
      y1 = (100 - 80 * Math.sin(theta1)).round(3)
      color = gauge_color((t0 + t1) / 2.0, stops)
      %(<path d="M #{x0},#{y0} A 80,80 0 0,1 #{x1},#{y1}" fill="none" stroke="#{color}" stroke-width="12"/>)
    end.join

    c0 = gauge_color(0.0, stops)
    c1 = gauge_color(1.0, stops)

    theta = Math::PI * (1.0 - t)
    nx    = (100 + 65 * Math.cos(theta)).round(1)
    ny    = (100 - 65 * Math.sin(theta)).round(1)
    nc    = missing ? "#9ca3af" : "#111827"

    <<~SVG.html_safe
      <svg viewBox="-10 -5 220 140" width="100%" xmlns="http://www.w3.org/2000/svg" style="display:block">
        <path d="M 20,100 A 80,80 0 0,1 180,100" fill="none" stroke="#e5e7eb" stroke-width="12" stroke-linecap="round"/>
        #{segs}
        <circle cx="20"  cy="100" r="6" fill="#{c0}"/>
        <circle cx="180" cy="100" r="6" fill="#{c1}"/>
        <text x="2"   y="115" font-size="8" text-anchor="start"  fill="#9ca3af">強空</text>
        <text x="22"  y="57"  font-size="8" text-anchor="middle" fill="#9ca3af">空</text>
        <text x="100" y="10"  font-size="8" text-anchor="middle" fill="#9ca3af">中性</text>
        <text x="178" y="57"  font-size="8" text-anchor="middle" fill="#9ca3af">多</text>
        <text x="198" y="115" font-size="8" text-anchor="end"    fill="#9ca3af">強多</text>
        <line x1="100" y1="100" x2="#{nx}" y2="#{ny}" stroke="#{nc}" stroke-width="2.5" stroke-linecap="round"/>
        <circle cx="100" cy="100" r="5" fill="#{nc}"/>
        <text x="100" y="131" font-size="13" font-weight="bold" text-anchor="middle" fill="#{nc}">#{label}</text>
      </svg>
    SVG
  end


  # ---------------------------------------------------------------------------
  # Options Flow detailed breakdown panel
  # ---------------------------------------------------------------------------
  def render_flow_detail
    flow = @result[:options_flow]
    if flow[:missing]
      render_barchart_login_prompt if @scrape_status == :session_expired
      return
    end

    call_prem  = flow[:call_premium_total].to_i
    put_prem   = flow[:put_premium_total].to_i
    total_prem = call_prem + put_prem
    return if total_prem == 0

    call_pct = (call_prem.to_f / total_prem * 100).round(1)
    put_pct  = (100 - call_pct).round(1)
    ratio    = flow[:call_put_ratio]
    ask_ratio = flow[:ask_call_put_ratio]

    ask_call = flow[:ask_call_premium].to_i
    ask_put  = flow[:ask_put_premium].to_i
    ask_total = ask_call + ask_put

    lg_call    = flow[:large_call_count].to_i
    lg_put     = flow[:large_put_count].to_i
    total_t    = flow[:total_trades].to_i
    high_delta = flow[:high_delta_call].to_i
    long_dte   = flow[:long_dte_call_prem].to_i
    short_dte  = flow[:short_dte_put_prem].to_i
    top_orders = Array(flow[:top_large_orders])

    div(class: "rounded-xl border border-gray-200 bg-white p-4 space-y-4") do
      # Header
      div(class: "flex items-center justify-between") do
        p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider") { plain "Options Flow 細節" }
        span(class: "text-xs text-gray-400") { plain "#{total_t} 筆交易" } if total_t > 0
      end

      # --- Section 1: Total C/P bar + Ask-side C/P ---
      div(class: "space-y-2") do
        p(class: "text-xs font-semibold text-gray-500 mb-1") { plain "全量 Call vs Put（含 bid/mid）" }
        div(class: "flex justify-between text-xs mb-0.5") do
          span(class: "text-green-600 font-medium") { plain "Call $#{sprintf("%.1f", call_prem / 1_000_000.0)}M (#{call_pct}%)" }
          span(class: "text-red-500 font-medium")  { plain "Put $#{sprintf("%.1f", put_prem / 1_000_000.0)}M (#{put_pct}%)" }
        end
        div(class: "h-3 rounded-full bg-red-200 overflow-hidden flex") do
          div(class: "h-full bg-green-600 rounded-l-full", style: "width:#{call_pct}%")
        end
        div(class: "flex items-center gap-4 mt-1") do
          if ratio
            ratio_color = ratio >= 1.5 ? "text-green-600" : ratio <= 0.67 ? "text-red-600" : "text-gray-500"
            span(class: "text-xs #{ratio_color} font-semibold") { plain "總 C/P 比率 #{sprintf("%.2f", ratio)}" }
          end
          if ask_ratio
            ask_color = ask_ratio >= 1.5 ? "text-green-700" : ask_ratio <= 0.67 ? "text-red-700" : "text-gray-500"
            span(class: "text-xs #{ask_color} font-bold") { plain "Ask-only C/P #{sprintf("%.2f", ask_ratio)} ★" }
          end
        end
      end

      # --- Section 2: Ask-side breakdown ---
      div(class: "pt-2 border-t border-gray-100") do
        p(class: "text-xs font-semibold text-gray-500 mb-1") { plain "主動買（Ask 成交 — 最具方向意義）" }
        if ask_total > 0
          ask_call_pct = (ask_call.to_f / ask_total * 100).round(1)
          div(class: "flex justify-between text-xs mb-0.5") do
            span(class: "text-green-600") { plain "Call $#{sprintf("%.1f", ask_call / 1_000_000.0)}M (#{ask_call_pct}%)" }
            span(class: "text-red-500")  { plain "Put $#{sprintf("%.1f", ask_put / 1_000_000.0)}M (#{(100 - ask_call_pct).round(1)}%)" }
          end
          div(class: "h-2 rounded-full bg-red-100 overflow-hidden") do
            div(class: "h-full bg-green-500 rounded-l-full", style: "width:#{ask_call_pct}%")
          end
        else
          p(class: "text-xs text-gray-400") { plain "無 Ask 成交紀錄" }
        end
      end

      # --- Section 3: Key indicators row ---
      div(class: "grid grid-cols-3 gap-2 pt-2 border-t border-gray-100") do
        # Large orders
        div(class: "text-center") do
          p(class: "text-xs font-semibold text-gray-500 mb-1") { plain "大單 (≥$500K)" }
          div(class: "flex justify-center gap-3") do
            div do
              p(class: "text-base font-bold text-blue-500") { plain lg_call.to_s }
              p(class: "text-xs text-gray-400") { plain "Call" }
            end
            div do
              p(class: "text-base font-bold text-red-500") { plain lg_put.to_s }
              p(class: "text-xs text-gray-400") { plain "Put" }
            end
          end
        end
        # High-delta calls
        div(class: "text-center") do
          p(class: "text-xs font-semibold text-gray-500 mb-1") { plain "高 Delta Call" }
          p(class: "text-xs text-gray-400 mb-0.5") { plain "≥0.70 ask-side" }
          p(class: "text-base font-bold #{high_delta >= 2 ? "text-green-600" : "text-gray-400"}") { plain high_delta.to_s }
        end
        # DTE signals
        div do
          p(class: "text-xs font-semibold text-gray-500 mb-1") { plain "DTE 分析" }
          if long_dte >= 100_000
            div(class: "flex items-center gap-1 mb-0.5") do
              span(class: "text-blue-400 text-xs") { plain "▲" }
              span(class: "text-xs text-blue-600") { plain "長線 $#{sprintf("%.1f", long_dte / 1_000_000.0)}M" }
            end
          end
          if short_dte >= 100_000
            div(class: "flex items-center gap-1") do
              span(class: "text-red-400 text-xs") { plain "▼" }
              span(class: "text-xs text-red-600") { plain "短期對沖 $#{sprintf("%.1f", short_dte / 1_000_000.0)}M" }
            end
          end
          if long_dte < 100_000 && short_dte < 100_000
            p(class: "text-xs text-gray-400") { plain "無顯著 DTE 訊號" }
          end
        end
      end

      # --- Section 4: Top large orders table ---
      unless top_orders.empty?
        div(class: "pt-2 border-t border-gray-100") do
          p(class: "text-xs font-semibold text-gray-500 mb-2") { plain "前十大單明細（依 Premium 排序）" }
          div(class: "overflow-x-auto") do
            table(class: "w-full text-xs") do
              thead do
                tr(class: "text-gray-400 border-b border-gray-100") do
                  th(class: "text-left py-1 pr-2 font-medium") { plain "型別" }
                  th(class: "text-right py-1 pr-2 font-medium") { plain "Strike" }
                  th(class: "text-right py-1 pr-2 font-medium") { plain "Price" }
                  th(class: "text-left py-1 pr-2 font-medium") { plain "到期" }
                  th(class: "text-right py-1 pr-2 font-medium") { plain "DTE" }
                  th(class: "text-center py-1 pr-2 font-medium") { plain "Side" }
                  th(class: "text-right py-1 pr-2 font-medium") { plain "Premium" }
                  th(class: "text-right py-1 pr-2 font-medium") { plain "Delta" }
                  th(class: "text-left py-1 font-medium") { plain "解讀" }
                end
              end
              tbody do
                top_orders.each do |ord|
                  is_call    = ord["symbolType"] == "Call"
                  type_color = is_call ? "text-green-700 font-bold" : "text-red-700 font-bold"
                  side_str   = (ord["side"] || "mid").downcase
                  side_color = case side_str
                               when "ask" then "text-green-600 font-bold"
                               when "bid" then "text-red-600 font-bold"
                               else            "text-amber-600 font-bold"
                               end
                  exp        = format_expiry(ord["expiration"])
                  delta_val  = ord["delta"] ? sprintf("%.2f", ord["delta"].to_f.abs) : "—"
                  prem_m     = ord["premium"] ? "$#{ord['premium'].to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}" : "—"
                  trade_price = if ord["lastPrice"]
                                  sprintf("$%.2f", ord["lastPrice"].to_f)
                                elsif ord["premium"] && ord["tradeSize"].to_i > 0
                                  sprintf("$%.2f", ord["premium"].to_f / (ord["tradeSize"].to_i * 100))
                                else
                                  "—"
                                end
                  driver     = flow_driver(ord)
                  tr(class: "border-b border-gray-100 hover:bg-purple-50") do
                    td(class: "py-1 pr-2 #{type_color}") { plain is_call ? "Call" : "Put" }
                    td(class: "py-1 pr-2 text-right font-mono text-gray-700") { plain ord["strikePrice"].to_s }
                    td(class: "py-1 pr-2 text-right font-mono text-gray-600") { plain trade_price }
                    td(class: "py-1 pr-2 text-gray-500") { plain exp }
                    td(class: "py-1 pr-2 text-right text-gray-500") { plain (ord["dte"] || "—").to_s }
                    td(class: "py-1 pr-2 text-center") do
                      span(class: side_color) { plain side_str.upcase }
                    end
                    td(class: "py-1 pr-2 text-right font-medium #{type_color}") { plain prem_m }
                    td(class: "py-1 pr-2 text-right text-gray-500") { plain delta_val }
                    td(class: "py-1 text-gray-500 whitespace-nowrap") { plain driver }
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def render_barchart_login_prompt
    div(class: "rounded-xl border border-amber-200 bg-amber-50 p-4") do
      div(class: "flex items-start gap-3") do
        span(class: "text-2xl leading-none mt-0.5") { plain "🔑" }
        div do
          p(class: "font-semibold text-sm text-amber-800") { plain "需要登入 Barchart 才能載入 Options Flow" }
          p(class: "text-sm text-amber-700 mt-1 leading-relaxed") do
            plain "請在 Chrome 前往 "
            a(href: "https://www.barchart.com/login", target: "_blank",
              class: "underline font-medium hover:text-amber-900") { plain "barchart.com" }
            plain "，用 Google 帳號登入後，回來重新查詢。"
          end
          p(class: "text-xs text-amber-600 mt-1.5") { plain "系統使用你目前 Chrome 中的登入 session，無需在此輸入密碼。" }
        end
      end
    end
  end

  def flow_driver(ord)
    type  = ord["symbolType"].to_s
    side  = (ord["side"] || "mid").downcase
    dte   = ord["dte"].to_i
    delta = ord["delta"].to_f.abs

    if type == "Call"
      case side
      when "ask"
        if delta >= 0.70 then "高確信看多押注"
        elsif dte > 180  then "長線機構佈局"
        else                  "主動看多"
        end
      when "bid" then "造市商賣出（中性）"
      else             "方向不明"
      end
    else
      case side
      when "ask"
        dte < 30 ? "短線緊急對沖" : "主動看空/對沖"
      when "bid" then "造市商賣 Put（中性）"
      else             "方向不明"
      end
    end
  end

  def format_expiry(exp_str)
    return "—" if exp_str.nil? || exp_str.empty?
    # Handle "MM/DD/YY" format
    if exp_str.match?(/^\d{2}\/\d{2}\/\d{2}$/)
      m, d, y = exp_str.split("/")
      return "#{m}/#{d}/#{y}"
    end
    # Handle ISO timestamp "2027-01-15T..."
    if exp_str.match?(/^(\d{4})-(\d{2})-(\d{2})/)
      m = exp_str.match(/^(\d{4})-(\d{2})-(\d{2})/)
      return "#{m[2]}/#{m[3]}/#{m[1][2..]}"
    end
    exp_str.to_s[0, 10]
  end

  # ---------------------------------------------------------------------------
  # Divergence warnings
  # ---------------------------------------------------------------------------
  def render_divergences
    divs = @result[:divergences]
    return if divs.empty?

    div(class: "space-y-2") do
      h2(class: "text-sm font-semibold text-gray-700") { plain "背離分析" }
      divs.each do |div_item|
        meta = DIV_META[div_item[:level]] || DIV_META[:caution]
        div(class: "flex items-start gap-3 px-4 py-3 rounded-lg border #{meta[:bg]} #{meta[:border]}") do
          span(class: "text-sm leading-none flex-shrink-0") { plain meta[:icon] }
          p(class: "text-sm #{meta[:text]} leading-relaxed") { plain div_item[:message] }
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Collapsible raw data detail
  # ---------------------------------------------------------------------------
  def render_data_detail
    fund = @result[:fetched_at]
    ts   = @result.dig(:technical, :signals)
    fs   = @result.dig(:fundamental, :signals)
    os   = @result.dig(:options_flow, :signals)

    details(class: "group rounded-xl border border-gray-200 bg-white overflow-hidden") do
      summary(class: "px-5 py-3 text-sm font-medium text-gray-600 cursor-pointer " \
                     "hover:bg-gray-50 flex items-center justify-between select-none") do
        span { plain "詳細訊號" }
        span(class: "text-gray-400 text-xs") { plain "▼" }
      end

      div(class: "px-5 py-4 grid grid-cols-3 gap-6 border-t border-gray-100") do
        render_signal_list("技術面訊號", ts)
        render_signal_list("基本面訊號", fs)
        render_signal_list("Options Flow 訊號", os)
      end
    end
  end

  def render_signal_list(title, signals)
    div do
      p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2") { plain title }
      if signals.blank?
        p(class: "text-xs text-gray-400 italic") { plain "無資料" }
      else
        div(class: "space-y-1.5") do
          signals.each do |sig|
            dot = SIGNAL_DOT[sig[:sentiment]] || "bg-gray-300"
            div(class: "flex items-start gap-2") do
              span(class: "w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0 #{dot}")
              span(class: "text-xs text-gray-600 leading-snug") { plain sig[:text] }
            end
          end
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # JS: show loading state when form submits
  # ---------------------------------------------------------------------------
  def render_loading_script
    script do
      raw <<~JS.html_safe
        (function () {
          var form    = document.getElementById('td-form');
          var btn     = document.getElementById('td-submit-btn');
          var loading = document.getElementById('td-loading');
          if (!form || !btn || !loading) return;

          form.addEventListener('submit', function () {
            btn.disabled = true;
            btn.textContent = '分析中…';
            btn.classList.add('opacity-50', 'cursor-not-allowed');
            loading.classList.remove('hidden');
            loading.classList.add('flex');
          });

          // Auto-uppercase the input
          var inp = document.getElementById('td-symbol-input');
          if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });
        })();
      JS
    end
  end
end
