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

  def initialize(symbol: nil, date: Date.today, result: nil, scrape_status: nil, scrape_errors: [], recent_symbols: [], stock_quote: nil)
    @symbol        = symbol
    @date          = date
    @result        = result
    @scrape_status = scrape_status
    @scrape_errors    = Array(scrape_errors)
    @recent_symbols   = Array(recent_symbols)
    @stock_quote      = stock_quote
  end

  def view_template
    div(class: "space-y-6") do
      render_header
      render_search_form
      render_recent_symbols unless @recent_symbols.empty?
      render_stock_quote if @stock_quote
      render_status_bar if @scrape_status
      if @result
        render_score_row
        render_data_detail
        render_flow_detail
        render_divergences
        render_options_charts
      end
    end
    render_dte_filter_script
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
  # Stock quote bar
  # ---------------------------------------------------------------------------
  def render_stock_quote
    q        = @stock_quote
    price    = sprintf("%.2f", q[:price])
    chg      = q[:change]
    chg_p    = q[:change_p]
    chg_str  = sprintf("%+.2f (%+.2f%%)", chg, chg_p)
    up       = chg >= 0
    chg_cls  = up ? "text-green-600" : "text-red-600"
    ts_str   = q[:ts] > 0 ? Time.at(q[:ts]).in_time_zone("Eastern Time (US & Canada)").strftime("%m/%d/%y") : ""
    exch     = q[:exchange].present? ? " [#{q[:exchange]}]" : ""
    name_sym = [q[:name].presence, @symbol.presence].compact.join(" ")
    name_sym = "(#{@symbol})" if q[:name].blank? && @symbol.present?
    name_sym = "#{q[:name]} (#{@symbol})" if q[:name].present?

    div(class: "flex items-baseline gap-4 px-1") do
      div do
        p(class: "text-sm font-semibold text-gray-700") { plain name_sym }
        div(class: "flex items-baseline gap-2 mt-0.5") do
          span(class: "text-xl font-bold text-gray-900") { plain "$#{price}" }
          span(class: "text-sm font-medium #{chg_cls}") { plain chg_str }
          span(class: "text-xs text-gray-400") { plain "#{ts_str}#{exch}" }
        end
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

      # --- Section 5: CSV BuyToOpen / SellToOpen 分類統計 ---
      if flow[:trade_csv_loaded]
        bto_call_prem = flow[:bto_call_ask_prem].to_i
        bto_put_prem  = flow[:bto_put_ask_prem].to_i
        sto_put_prem  = flow[:sto_put_bid_prem].to_i
        bto_call_cnt  = flow[:bto_call_ask_cnt].to_i
        bto_put_cnt   = flow[:bto_put_ask_cnt].to_i
        sto_put_cnt   = flow[:sto_put_bid_cnt].to_i
        dir_count     = flow[:directional_count].to_i
        ml_count      = flow[:multi_leg_count].to_i
        canc_count    = flow[:cancelled_count].to_i
        inst_count    = flow[:institutional_count].to_i

        div(class: "pt-2 border-t border-gray-100") do
          p(class: "text-xs font-semibold text-gray-500 mb-2") { plain "CSV 開倉方向統計（BuyToOpen / SellToOpen）" }
          div(class: "grid grid-cols-3 gap-2") do
            div(class: "text-center") do
              p(class: "text-base font-bold text-green-600") { plain "$#{sprintf("%.1f", bto_call_prem / 1_000_000.0)}M" }
              p(class: "text-xs text-gray-500") { plain "BTO Call Ask" }
              p(class: "text-xs text-gray-400") { plain "#{bto_call_cnt} 筆 ↑ 開倉看多" }
            end
            div(class: "text-center") do
              p(class: "text-base font-bold text-red-500") { plain "$#{sprintf("%.1f", bto_put_prem / 1_000_000.0)}M" }
              p(class: "text-xs text-gray-500") { plain "BTO Put Ask" }
              p(class: "text-xs text-gray-400") { plain "#{bto_put_cnt} 筆 ↓ 開倉看空/避險" }
            end
            div(class: "text-center") do
              p(class: "text-base font-bold text-blue-500") { plain "$#{sprintf("%.1f", sto_put_prem / 1_000_000.0)}M" }
              p(class: "text-xs text-gray-500") { plain "STO Put Bid" }
              p(class: "text-xs text-gray-400") { plain "#{sto_put_cnt} 筆 ↑ 賣 Put 收租" }
            end
          end
          div(class: "flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs text-gray-400") do
            span { plain "方向性 #{dir_count} 筆" }
            span { plain "多腿排除 #{ml_count} 筆" }
            span { plain "取消排除 #{canc_count} 筆" }
            span { plain "機構 #{inst_count} 筆" } if inst_count > 0
          end
        end
      end

      # --- Section 4: Top large orders table ---
      unless top_orders.empty?
        div(class: "pt-2 border-t border-gray-100") do
          div(class: "flex items-center justify-between mb-2") do
            p(class: "text-xs font-semibold text-gray-500") { plain "前二十大單明細（依 Premium 排序）" }
            button(
              id:    "dte-filter-btn",
              type:  "button",
              class: "px-2.5 py-0.5 rounded-full text-xs border border-gray-300 text-gray-500 " \
                     "hover:border-purple-400 hover:text-purple-600 transition-colors select-none"
            ) { plain "排除 DTE=0" }
          end
          div(class: "overflow-x-auto") do
            table(class: "w-full text-2xl") do
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
                top_orders.each_with_index do |ord, idx|
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
                  trade_price = if ord["tradePrice"] && ord["tradePrice"].to_f > 0
                                  sprintf("$%.2f", ord["tradePrice"].to_f)
                                elsif ord["premium"].to_f > 0 && ord["tradeSize"].to_i > 0
                                  sprintf("$%.2f", ord["premium"].to_f / (ord["tradeSize"].to_i * 100))
                                else
                                  "—"
                                end
                  driver       = flow_driver(ord)
                  driver_tip   = flow_driver_tip(ord)
                  price_color  = case side_str
                                 when "ask" then "text-green-600 font-bold"
                                 when "bid" then "text-red-600 font-bold"
                                 else            "text-gray-900 font-bold"
                                 end
                  tr(class: "border-b border-gray-100 hover:bg-purple-50", "data-dte": (ord["dte"] || -1).to_s, "data-rank": (idx + 1).to_s) do
                    td(class: "py-1 pr-2 #{type_color}") { plain is_call ? "Call" : "Put" }
                    td(class: "py-1 pr-2 text-right font-mono text-gray-700") { plain ord["strikePrice"].to_s }
                    td(class: "py-1 pr-2 text-right font-mono #{price_color}") { plain trade_price }
                    td(class: "py-1 pr-2 text-gray-500") { plain exp }
                    td(class: "py-1 pr-2 text-right text-gray-500") { plain (ord["dte"] || "—").to_s }
                    td(class: "py-1 pr-2 text-center") do
                      span(class: side_color) { plain side_str.upcase }
                    end
                    td(class: "py-1 pr-2 text-right font-medium #{type_color}") { plain prem_m }
                    td(class: "py-1 pr-2 text-right text-gray-500") { plain delta_val }
                    td("data-tooltip": driver_tip, class: "py-1 text-gray-600 whitespace-nowrap") { plain driver }
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

  def flow_driver_tip(ord)
    type  = ord["symbolType"].to_s
    side  = (ord["side"] || "mid").downcase
    dte   = ord["dte"].to_i
    delta = ord["delta"].to_f.abs
    strike = ord["strikePrice"]
    parts = []
    parts << "#{type} $#{strike}"  if strike
    parts << "DTE #{dte}"          if dte > 0
    parts << "Delta #{sprintf("%.2f", delta)}" if delta > 0
    parts << case side
             when "ask" then "ASK：主動買入（方向性）"
             when "bid" then "BID：造市商賣出（非方向性）"
             else            "MID：方向不明"
             end
    if type == "Call" && side == "ask"
      parts << (delta >= 0.70 ? "高 Delta — 強確信押注" : dte > 180 ? "長線 — 機構佈局" : "看多押注")
    elsif type == "Put" && side == "ask"
      parts << (dte < 30 ? "短 DTE — 緊急對沖" : "看空/對沖")
    end
    parts.join(" | ")
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
  def render_options_charts
    mp = @result&.dig(:max_pain)
    return unless mp && mp[:strikes]&.any?

    symbol       = @result[:symbol]
    strikes      = mp[:strikes].map(&:to_s)
    call_pain    = mp[:call_pain]
    put_pain     = mp[:put_pain]
    call_oi      = mp[:call_oi]
    put_oi       = mp[:put_oi].map { |v| -(v.abs) }
    iv_combined  = mp[:iv_combined]
    max_pain_str = mp[:max_pain_strike]
    last_price   = mp[:last_price]
    expiration   = mp[:expiration]&.gsub(/-m$/, "")
    dte          = mp[:dte]
    by_expiry    = mp[:max_pain_by_expiry] || []

    exp_label    = expiration ? "#{expiration} (#{dte} DTE)" : ""

    pain_json    = { strikes: strikes, call_pain: call_pain, put_pain: put_pain,
                     max_pain_strike: max_pain_str, last_price: last_price,
                     exp_label: exp_label, symbol: symbol }.to_json
    oi_json      = { strikes: strikes, call_oi: call_oi, put_oi: put_oi,
                     last_price: last_price, exp_label: exp_label, symbol: symbol }.to_json
    skew_json    = { strikes: strikes, iv_combined: iv_combined,
                     last_price: last_price, exp_label: exp_label, symbol: symbol }.to_json
    contract_json = { by_expiry: by_expiry, last_price: last_price, symbol: symbol }.to_json

    div(class: "bg-white rounded-xl border border-gray-200 p-4 space-y-6") do
      h2(class: "text-sm font-semibold text-gray-700") { "Max Pain & Vol Skew" }

      # Chart 1: Max Pain
      div do
        div(class: "relative", style: "height:260px") do
          canvas(id: "mp-c1-#{symbol}", class: "w-full h-full")
        end
        script(type: "application/json", id: "mp-d1-#{symbol}") { raw pain_json.html_safe }

          p(class: "text-amber-600 font-semibold mt-1", style: "font-size:14px") { raw "⚠️ Max Pain 判讀提醒".html_safe }
            div(class: "mt-1 text-gray-500 leading-relaxed bg-amber-50 rounded p-2 space-y-1", style: "font-size:22px") do
              p { "Max Pain 理論假設選擇權賣方有能力將股價推向 OI 最集中的價位，但在市值大、流動性好的標的上，股票本身的成交量遠大於選擇權的槓桿影響力，此效應通常較弱。" }
              p { raw "遠月合約 OI 結構較為分散，深度價外的高 OI 較可能反映 PMCC 長腿或長期避險需求，<strong>不宜直接解讀為方向性訊號</strong>。".html_safe }
              p { raw "<strong>使用建議</strong>：僅作為「到期日附近短期磁吸效應」的參考，到期日越遠，參考價值越低。".html_safe }
            end
      end

      # Chart 2: Open Interest by Strike
      div do
        div(class: "relative", style: "height:220px") do
          canvas(id: "mp-c2-#{symbol}", class: "w-full h-full")
        end
        script(type: "application/json", id: "mp-d2-#{symbol}") { raw oi_json.html_safe }

          p(class: "text-amber-600 font-semibold mt-1", style: "font-size:14px") { raw "⚠️ OI 分布判讀提醒".html_safe }
            div(class: "mt-1 text-gray-500 leading-relaxed bg-amber-50 rounded p-2 space-y-1", style: "font-size:22px") do
              p { "高 OI 集中的 strike 無法直接判斷多空方向：Put OI 可能是保護性避險（偏空），也可能是賣 Put 收保費（偏多）；Call OI 同理。" }
              p { raw "<strong>使用建議</strong>：須搭配 Options Flow 的 Trade 方向（成交於 Ask 或 Bid）及 Code 交叉比對，不可單憑 OI 集中度判斷。".html_safe }
            end
      end

      # Chart 3: Vol Skew
      div do
        div(class: "relative", style: "height:220px") do
          canvas(id: "mp-c3-#{symbol}", class: "w-full h-full")
        end
        script(type: "application/json", id: "mp-d3-#{symbol}") { raw skew_json.html_safe }

          p(class: "text-amber-600 font-semibold mt-1", style: "font-size:14px") { raw "⚠️ Vol Skew 判讀提醒".html_safe }
            div(class: "mt-1 text-gray-500 leading-relaxed bg-amber-50 rounded p-2 space-y-1", style: "font-size:22px") do
              p { "下傾斜（Put 端 IV 高於 Call 端）是選擇權市場的結構性常態，反映避險需求長期偏 Put，本身不是看空訊號。" }
              p { raw "單一時間點的 Skew 形狀<strong>不具判斷力</strong>，必須與該標的自身歷史 Skew 比較（Skew Rank）才能判斷是否異常。".html_safe }
              p { raw "<strong>使用建議</strong>：本圖為單次快照，需對照歷史 Skew 百分位，不可僅憑曲線形狀下結論。".html_safe }
            end
      end

      # Chart 4: Max Pain by Contract
      div do
        div(class: "relative", style: "height:200px") do
          canvas(id: "mp-c4-#{symbol}", class: "w-full h-full")
        end
        script(type: "application/json", id: "mp-d4-#{symbol}") { raw contract_json.html_safe }

          p(class: "text-amber-600 font-semibold mt-1", style: "font-size:14px") { raw "⚠️ Max Pain by Expiry 判讀提醒".html_safe }
            div(class: "mt-1 text-gray-500 leading-relaxed bg-amber-50 rounded p-2 space-y-1", style: "font-size:22px") do
              p { "若某個到期日的數值明顯偏離其他到期日，優先檢查是否緊鄰財報公布日期。" }
              p { "財報前後市場會大量布局跨事件選擇權倉位，使該到期日的 OI 結構暫時失真，Max Pain 的參考價值會明顯降低。" }
              p { raw "<strong>使用建議</strong>：財報前後 14 天內的到期日數據，Max Pain 可信度打折。".html_safe }
            end
      end
    end

    script do
      raw <<~JS.html_safe
        (function () {
          var sym = #{symbol.to_json};

          // Vertical line plugin — category scale: find nearest label index
          var vlinePlugin = {
            id: 'mp_vline_' + sym,
            afterDraw: function(chart) {
              var lines = chart.options.vlines;
              if (!lines || !lines.length) return;
              var ctx   = chart.ctx;
              var xAxis = chart.scales.x;
              var yAxis = chart.scales.y;
              var labels = xAxis.getLabels ? xAxis.getLabels() : [];
              lines.forEach(function(vl) {
                var xPx;
                if (labels.length > 0) {
                  var nearestIdx = 0, minDiff = Infinity;
                  labels.forEach(function(lbl, idx) {
                    var diff = Math.abs(parseFloat(lbl) - vl.value);
                    if (diff < minDiff) { minDiff = diff; nearestIdx = idx; }
                  });
                  xPx = xAxis.getPixelForValue(nearestIdx);
                } else {
                  xPx = xAxis.getPixelForValue(vl.value);
                }
                if (!xPx || xPx < xAxis.left || xPx > xAxis.right) return;
                ctx.save();
                ctx.beginPath();
                ctx.setLineDash(vl.dash || []);
                ctx.strokeStyle = vl.color || 'rgba(0,0,0,0.4)';
                ctx.lineWidth   = 1.5;
                ctx.moveTo(xPx, yAxis.top);
                ctx.lineTo(xPx, yAxis.bottom);
                ctx.stroke();
                if (vl.label) {
                  ctx.fillStyle = vl.color || 'rgba(0,0,0,0.5)';
                  ctx.font = '10px sans-serif';
                  ctx.fillText(vl.label, xPx + 3, yAxis.top + 12);
                }
                ctx.restore();
              });
            }
          };

          var GRID   = '#e5e7eb';
          var TICK   = { color: '#6b7280', font: { size: 10 } };
          var LEGEND = { position: 'top', labels: { color: '#6b7280', font: { size: 11 }, boxWidth: 12 } };

          // ── Chart 1: Max Pain ──────────────────────────────────────────
          (function() {
            var el = document.getElementById('mp-d1-' + sym);
            var cv = document.getElementById('mp-c1-' + sym);
            if (!el || !cv || typeof Chart === 'undefined') return;
            var d = JSON.parse(el.textContent);
            new Chart(cv, {
              type: 'bar',
              plugins: [vlinePlugin],
              data: {
                labels: d.strikes,
                datasets: [
                  { label: 'Calls - Max Pain', data: d.call_pain,
                    backgroundColor: 'rgba(34,197,94,0.65)', borderColor: 'rgba(22,163,74,0.8)',
                    borderWidth: 1, borderRadius: 2 },
                  { label: 'Puts - Max Pain', data: d.put_pain,
                    backgroundColor: 'rgba(239,68,68,0.65)', borderColor: 'rgba(220,38,38,0.8)',
                    borderWidth: 1, borderRadius: 2 }
                ]
              },
              options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                plugins: { legend: LEGEND,
                  tooltip: {
                    enabled: false, mode: 'index', intersect: false,
                    external: function(context) {
                      var tipId = 'mp-tip-' + sym;
                      var tipEl = document.getElementById(tipId);
                      if (!tipEl) {
                        tipEl = document.createElement('div');
                        tipEl.id = tipId;
                        tipEl.style.cssText = 'position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.97);border:1px solid #d1d5db;border-radius:4px;padding:7px 11px;font-size:11px;line-height:1.7;z-index:10;pointer-events:none;box-shadow:0 2px 6px rgba(0,0,0,0.13);min-width:140px;';
                        cv.parentElement.appendChild(tipEl);
                      }
                      var tip = context.tooltip;
                      if (tip.opacity === 0) { tipEl.style.opacity='0'; return; }
                      tipEl.style.opacity = '1';
                      var strike = tip.title && tip.title[0] ? tip.title[0] : '';
                      var callVal = null, putVal = null;
                      (tip.dataPoints || []).forEach(function(dp) {
                        if (dp.dataset.label.indexOf('Call') >= 0) callVal = dp.raw;
                        else if (dp.dataset.label.indexOf('Put') >= 0) putVal = dp.raw;
                      });
                      function fmt(v) { return v != null ? '$' + Number(v).toLocaleString('en-US', {minimumFractionDigits:2}) : 'N/A'; }
                      tipEl.innerHTML =
                        '<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ' + strike + '</div>' +
                        '<div style="color:#16a34a;">Call: ' + fmt(callVal) + '</div>' +
                        '<div style="color:#dc2626;">Put: ' + fmt(putVal) + '</div>' +
                        (d.max_pain_strike ? '<div style="margin-top:4px;color:#2563eb;font-size:10px;">Max Pain: $' + d.max_pain_strike + '</div>' : '');
                    }
                  }
                },
                vlines: [
                  d.max_pain_strike ? { value: d.max_pain_strike, color: 'rgba(37,99,235,0.8)',  dash: [5,3], label: 'Max Pain $' + d.max_pain_strike } : null,
                  d.last_price      ? { value: d.last_price,      color: 'rgba(107,114,128,0.6)', dash: [4,3], label: 'Last $' + d.last_price.toFixed(2) } : null
                ].filter(Boolean),
                scales: {
                  x: { ticks: Object.assign({}, TICK, { maxRotation: 45 }), grid: { color: GRID } },
                  y: { ticks: Object.assign({}, TICK, { callback: function(v) { return v >= 1000 ? (v/1000).toFixed(0)+'k' : v; } }), grid: { color: GRID } }
                }
              }
            });
          })();

          // ── Chart 2: Open Interest by Strike ──────────────────────────
          (function() {
            var el = document.getElementById('mp-d2-' + sym);
            var cv = document.getElementById('mp-c2-' + sym);
            if (!el || !cv || typeof Chart === 'undefined') return;
            var d = JSON.parse(el.textContent);
            new Chart(cv, {
              type: 'bar',
              plugins: [vlinePlugin],
              data: {
                labels: d.strikes,
                datasets: [
                  { label: 'Call OI', data: d.call_oi,
                    backgroundColor: 'rgba(59,130,246,0.65)', borderColor: 'rgba(37,99,235,0.8)',
                    borderWidth: 1, borderRadius: 2 },
                  { label: 'Put OI', data: d.put_oi,
                    backgroundColor: 'rgba(249,115,22,0.65)', borderColor: 'rgba(234,88,12,0.8)',
                    borderWidth: 1, borderRadius: 2 }
                ]
              },
              options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                plugins: { legend: LEGEND,
                  tooltip: {
                    enabled: false, mode: 'index', intersect: false,
                    external: function(context) {
                      var tipId = 'mp-tip2-' + sym;
                      var tipEl = document.getElementById(tipId);
                      if (!tipEl) {
                        tipEl = document.createElement('div');
                        tipEl.id = tipId;
                        tipEl.style.cssText = 'position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.97);border:1px solid #d1d5db;border-radius:4px;padding:7px 11px;font-size:11px;line-height:1.7;z-index:10;pointer-events:none;box-shadow:0 2px 6px rgba(0,0,0,0.13);min-width:130px;';
                        cv.parentElement.appendChild(tipEl);
                      }
                      var tip = context.tooltip;
                      if (tip.opacity === 0) { tipEl.style.opacity='0'; return; }
                      tipEl.style.opacity = '1';
                      var strike = tip.title && tip.title[0] ? tip.title[0] : '';
                      var callOI = null, putOI = null;
                      (tip.dataPoints || []).forEach(function(dp) {
                        if (dp.dataset.label.indexOf('Call') >= 0) callOI = dp.raw;
                        else if (dp.dataset.label.indexOf('Put') >= 0) putOI = dp.raw;
                      });
                      function fmt(v) { return v != null ? Number(Math.abs(v)).toLocaleString('en-US') : 'N/A'; }
                      tipEl.innerHTML =
                        '<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ' + strike + '</div>' +
                        '<div style="color:#2563eb;">Call OI: ' + fmt(callOI) + '</div>' +
                        '<div style="color:#ea580c;">Put OI: ' + fmt(putOI) + '</div>';
                    }
                  }
                },
                vlines: d.last_price ? [{ value: d.last_price, color: 'rgba(107,114,128,0.6)', dash: [4,3], label: 'Last $' + d.last_price.toFixed(2) }] : [],
                scales: {
                  x: { ticks: Object.assign({}, TICK, { maxRotation: 45 }), grid: { color: GRID } },
                  y: { ticks: TICK, grid: { color: GRID } }
                }
              }
            });
          })();

          // ── Chart 3: Volatility Skew ───────────────────────────────────
          (function() {
            var el = document.getElementById('mp-d3-' + sym);
            var cv = document.getElementById('mp-c3-' + sym);
            if (!el || !cv || typeof Chart === 'undefined') return;
            var d = JSON.parse(el.textContent);
            new Chart(cv, {
              type: 'line',
              plugins: [vlinePlugin],
              data: {
                labels: d.strikes,
                datasets: [
                  { label: 'Call & Put IV (%)', data: d.iv_combined,
                    borderColor: 'rgba(234,179,8,0.9)', backgroundColor: 'rgba(234,179,8,0.08)',
                    borderWidth: 2, pointRadius: 2.5, pointBackgroundColor: 'rgba(234,179,8,0.9)',
                    fill: true, tension: 0.3 }
                ]
              },
              options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                plugins: { legend: LEGEND,
                  tooltip: {
                    enabled: false, mode: 'index', intersect: false,
                    external: function(context) {
                      var tipId = 'mp-tip3-' + sym;
                      var tipEl = document.getElementById(tipId);
                      if (!tipEl) {
                        tipEl = document.createElement('div');
                        tipEl.id = tipId;
                        tipEl.style.cssText = 'position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.97);border:1px solid #d1d5db;border-radius:4px;padding:7px 11px;font-size:11px;line-height:1.7;z-index:10;pointer-events:none;box-shadow:0 2px 6px rgba(0,0,0,0.13);min-width:120px;';
                        cv.parentElement.appendChild(tipEl);
                      }
                      var tip = context.tooltip;
                      if (tip.opacity === 0) { tipEl.style.opacity='0'; return; }
                      tipEl.style.opacity = '1';
                      var strike = tip.title && tip.title[0] ? tip.title[0] : '';
                      var iv = null;
                      (tip.dataPoints || []).forEach(function(dp) { if (dp.raw != null) iv = dp.raw; });
                      tipEl.innerHTML =
                        '<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ' + strike + '</div>' +
                        '<div style="color:#ca8a04;">IV: ' + (iv != null ? iv.toFixed(2) + '%' : 'N/A') + '</div>' +
                        (d.last_price ? '<div style="margin-top:4px;color:#6b7280;font-size:10px;">Last: $' + d.last_price.toFixed(2) + '</div>' : '');
                    }
                  }
                },
                vlines: d.last_price ? [{ value: d.last_price, color: 'rgba(107,114,128,0.6)', dash: [4,3], label: 'Last $' + d.last_price.toFixed(2) }] : [],
                scales: {
                  x: { ticks: Object.assign({}, TICK, { maxRotation: 45 }), grid: { color: GRID } },
                  y: { ticks: Object.assign({}, TICK, { callback: function(v) { return v.toFixed(1) + '%'; } }), grid: { color: GRID } }
                }
              }
            });
          })();

          // ── Chart 4: Max Pain by Contract ─────────────────────────────
          (function() {
            var el = document.getElementById('mp-d4-' + sym);
            var cv = document.getElementById('mp-c4-' + sym);
            if (!el || !cv || typeof Chart === 'undefined') return;
            var d = JSON.parse(el.textContent);
            if (!d.by_expiry || !d.by_expiry.length) return;
            var labels  = d.by_expiry.map(function(r) { return r.expiry; });
            var values  = d.by_expiry.map(function(r) { return r.max_pain_strike; });
            var lpLine  = d.last_price ? values.map(function() { return d.last_price; }) : [];
            new Chart(cv, {
              type: 'line',
              data: {
                labels: labels,
                datasets: [
                  { label: 'Max Pain by Expiry', data: values,
                    borderColor: 'rgba(59,130,246,0.9)', backgroundColor: 'rgba(59,130,246,0.1)',
                    borderWidth: 2, pointRadius: 4, pointBackgroundColor: 'rgba(59,130,246,0.9)',
                    fill: false, tension: 0 },
                  d.last_price ? { label: 'Last Price $' + d.last_price.toFixed(2), data: lpLine,
                    borderColor: 'rgba(236,72,153,0.7)', borderDash: [5,3],
                    borderWidth: 1.5, pointRadius: 0, fill: false } : null
                ].filter(Boolean)
              },
              options: {
                responsive: true, maintainAspectRatio: false, animation: false,
                plugins: { legend: LEGEND,
                  tooltip: {
                    enabled: false, mode: 'index', intersect: false,
                    external: function(context) {
                      var tipId = 'mp-tip4-' + sym;
                      var tipEl = document.getElementById(tipId);
                      if (!tipEl) {
                        tipEl = document.createElement('div');
                        tipEl.id = tipId;
                        tipEl.style.cssText = 'position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.97);border:1px solid #d1d5db;border-radius:4px;padding:7px 11px;font-size:11px;line-height:1.7;z-index:10;pointer-events:none;box-shadow:0 2px 6px rgba(0,0,0,0.13);min-width:150px;';
                        cv.parentElement.appendChild(tipEl);
                      }
                      var tip = context.tooltip;
                      if (tip.opacity === 0) { tipEl.style.opacity='0'; return; }
                      tipEl.style.opacity = '1';
                      var expiry = tip.title && tip.title[0] ? tip.title[0] : '';
                      var mpVal = null, lpVal = null;
                      (tip.dataPoints || []).forEach(function(dp) {
                        if (dp.dataset.label.indexOf('Max Pain') >= 0) mpVal = dp.raw;
                        else if (dp.dataset.label.indexOf('Last') >= 0) lpVal = dp.raw;
                      });
                      tipEl.innerHTML =
                        '<div style="font-weight:600;margin-bottom:2px;color:#111;">' + expiry + '</div>' +
                        '<div style="color:#2563eb;">Max Pain: $' + (mpVal != null ? mpVal.toFixed(2) : 'N/A') + '</div>' +
                        (lpVal != null ? '<div style="color:#db2777;">Last Price: $' + lpVal.toFixed(2) + '</div>' : '');
                    }
                  }
                },
                scales: {
                  x: { ticks: Object.assign({}, TICK, { maxRotation: 45 }), grid: { color: GRID } },
                  y: { ticks: Object.assign({}, TICK, { callback: function(v) { return '$' + v; } }), grid: { color: GRID } }
                }
              }
            });
          })();
        })();
      JS
    end
  end


  def render_dte_filter_script
    script do
      raw <<~JS.html_safe
        (function () {
          var btn = document.getElementById('dte-filter-btn');
          if (!btn) return;
          var active = false;

          function applyDisplay() {
            var rows = Array.from(document.querySelectorAll('tr[data-rank]'));
            var visible = 0;
            rows.forEach(function (row) {
              var dte  = parseInt(row.dataset.dte, 10);
              var show = (!active || dte !== 0) && visible < 20;
              if (show) visible++;
              row.style.display = show ? '' : 'none';
            });
          }

          applyDisplay();

          btn.addEventListener('click', function () {
            active = !active;
            btn.textContent = active ? '全部顯示' : '排除 DTE=0';
            btn.classList.toggle('bg-purple-100',    active);
            btn.classList.toggle('border-purple-500', active);
            btn.classList.toggle('text-purple-700',  active);
            applyDisplay();
          });
        })();
      JS
    end
  end

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
