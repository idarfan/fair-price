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
    warning:      { bg: "bg-orange-900/30", border: "border-orange-500/40", icon: "⚠️", text: "text-orange-300" },
    caution:      { bg: "bg-yellow-900/20", border: "border-yellow-500/30", icon: "💡", text: "text-yellow-300" },
    confirm_bull: { bg: "bg-green-900/20",  border: "border-green-500/30",  icon: "✅", text: "text-green-300" },
    confirm_bear: { bg: "bg-red-900/20",    border: "border-red-500/30",    icon: "🔴", text: "text-red-300" }
  }.freeze

  def initialize(symbol: nil, result: nil, scrape_status: nil, scrape_errors: [], recent_symbols: [])
    @symbol        = symbol
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
        render_divergences
        render_data_detail
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
        plain "使用 5 分鐘內快取資料"
        if @result&.[](:fetched_at)
          plain "（#{@result[:fetched_at].strftime("%H:%M:%S")}）"
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
        gauge_t:  technical_gauge_t(tech)
      )
      render_score_card(
        title:    "基本面",
        subtitle: "分析師評級 · EPS · P/E",
        data:     fund,
        gauge_t:  fundamental_gauge_t(fund)
      )
      render_score_card(
        title:    "Options Flow",
        subtitle: "淨情緒 · Delta Imbalance",
        data:     flow,
        gauge_t:  options_flow_gauge_t(flow)
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
    sigs  = Array(data[:signals])
    bulls = sigs.count { |s| s[:sentiment] == :bullish }
    bears = sigs.count { |s| s[:sentiment] == :bearish }
    return 0.85 if bulls >= 2
    return 0.15 if bears >= 2
    0.5
  end

  def render_score_card(title:, subtitle:, data:, gauge_t:)
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

    div(class: "rounded-xl border-2 bg-gray-900 p-4 space-y-3 #{border_class}") do
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
      raw(gauge_svg(t: gauge_t, missing: data[:missing]))

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
              span(class: "text-xs text-gray-400 leading-snug") { plain sig[:text] }
            end
          end
        end
      end
    end
  end

  def gauge_svg(t:, missing: false)
    t = missing ? 0.5 : t.clamp(0.0, 1.0)
    theta = Math::PI * (1.0 - t)
    nx    = (100 + 65 * Math.cos(theta)).round(1)
    ny    = (100 - 65 * Math.sin(theta)).round(1)

    # Needle base dot and line color
    needle_color = missing ? "#6b7280" : "#f3f4f6"

    <<~SVG.html_safe
      <svg viewBox="0 0 200 118" width="100%" xmlns="http://www.w3.org/2000/svg" style="display:block">
        <!-- Background track -->
        <path d="M 20,100 A 80,80 0 0,1 180,100" fill="none" stroke="#374151" stroke-width="10" stroke-linecap="round"/>
        <!-- Zone arcs -->
        <path d="M 20,100 A 80,80 0 0,1 35.3,53" fill="none" stroke="#ef4444" stroke-width="10" stroke-linecap="round"/>
        <path d="M 35.3,53 A 80,80 0 0,1 75.3,23.9" fill="none" stroke="#f87171" stroke-width="10"/>
        <path d="M 75.3,23.9 A 80,80 0 0,1 124.7,23.9" fill="none" stroke="#6b7280" stroke-width="10"/>
        <path d="M 124.7,23.9 A 80,80 0 0,1 164.7,53" fill="none" stroke="#818cf8" stroke-width="10"/>
        <path d="M 164.7,53 A 80,80 0 0,1 180,100" fill="none" stroke="#3b82f6" stroke-width="10" stroke-linecap="round"/>
        <!-- Zone labels -->
        <text x="10" y="114" font-size="8" text-anchor="middle" fill="#6b7280">強空</text>
        <text x="43" y="52" font-size="8" text-anchor="middle" fill="#6b7280">空</text>
        <text x="100" y="14" font-size="8" text-anchor="middle" fill="#6b7280">中性</text>
        <text x="157" y="52" font-size="8" text-anchor="middle" fill="#6b7280">多</text>
        <text x="190" y="114" font-size="8" text-anchor="middle" fill="#6b7280">強多</text>
        <!-- Needle -->
        <line x1="100" y1="100" x2="#{nx}" y2="#{ny}" stroke="#{needle_color}" stroke-width="2.5" stroke-linecap="round"/>
        <circle cx="100" cy="100" r="5" fill="#{needle_color}"/>
      </svg>
    SVG
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
