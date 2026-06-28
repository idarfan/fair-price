# frozen_string_literal: true

class LeapsRecommendations::PageComponent < ApplicationComponent
  LIQUIDITY_STYLE = {
    "充足" => { bg: "bg-green-50",  border: "border-green-300",  text: "text-green-800",  dot: "bg-green-400" },
    "普通" => { bg: "bg-yellow-50", border: "border-yellow-300", text: "text-yellow-800", dot: "bg-yellow-400" },
    "偏低" => { bg: "bg-orange-50", border: "border-orange-300", text: "text-orange-800", dot: "bg-orange-400" }
  }.freeze

  DIR_STYLE = {
    "bullish" => { dot: "bg-green-400", text: "text-green-700",  label: "偏多" },
    "bearish" => { dot: "bg-red-400",   text: "text-red-700",    label: "偏空" },
    "neutral" => { dot: "bg-gray-400",  text: "text-gray-600",   label: "中性" }
  }.freeze

  TABLE_COLS = [
    "到期日", "DTE", "履約價", "Delta", "OI", "Volume", "流動性判斷",
    "Bid", "Ask", "Mid", "Spread%", "Time Value%", "IV", "Vega", "被指派機率"
  ].freeze

  FLOW_COLS = [ "類型", "履約價", "到期日", "DTE", "Delta", "Code", "Size", "Side", "Premium", "方向" ].freeze

  def initialize(symbol: nil, candidates: [], recommendation: nil, flow_panel: nil, scrape_status: nil, scrape_errors: [])
    @symbol         = symbol
    @candidates     = Array(candidates)
    @recommendation = recommendation
    @flow_panel     = flow_panel
    @scrape_status  = scrape_status
    @scrape_errors  = Array(scrape_errors)
  end

  def view_template
    div(class: "space-y-6") do
      render_header
      render_search_form
      render_status_bar if @scrape_status
      if @candidates.any?
        render_recommendation if @recommendation
        render_ranking_table
        render_flow_panel if @flow_panel
      end
    end
    render_loading_script
  end

  private

  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") { plain "LEAPS Call 候選排行" }
      p(class: "text-sm text-gray-500 mt-0.5") { plain "Delta 0.75–0.90 深度價內 Call · 依 OI 由高到低排序" }
    end
  end

  def render_search_form
    form(id: "leaps-form", action: "/leaps", method: "get", class: "flex items-center gap-3") do
      input(
        id: "leaps-symbol-input", type: "text", name: "symbol",
        value: @symbol.to_s, placeholder: "輸入股票代號，例如 NOK",
        maxlength: "10",
        class: "w-48 px-4 py-2 rounded-lg border border-gray-300 text-sm font-mono uppercase " \
               "focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
      )
      button(
        id: "leaps-submit-btn", type: "submit",
        class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
      ) { plain "查詢" }
      div(id: "leaps-loading", class: "hidden items-center gap-2 text-sm text-gray-500") do
        div(class: "w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin")
        plain "抓取資料中，請稍候…（約 3–5 分鐘）"
      end
    end
  end

  def render_status_bar
    case @scrape_status
    when :session_expired
      render_alert("bg-orange-50 border border-orange-300 text-orange-800",
        "⚠️ 請先登入 Barchart 後重試。（Barchart 登入 Session 已過期）")
    when :partial_error
      msg = @scrape_errors.first || "抓取中途 Session 過期，部分資料可能不完整。請重新登入 Barchart 後重試。"
      render_alert("bg-yellow-50 border border-yellow-300 text-yellow-800", "⚠️ #{msg}")
    when :error
      render_alert("bg-red-50 border border-red-300 text-red-800",
        "❌ CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動。若電腦曾經睡眠/喚醒，這通常是 WSL2 的 /mnt/c/ 掛載失效造成的，請在 Windows PowerShell 執行 wsl --shutdown 後等待 WSL2 重新啟動，再重試一次。")
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
        div(class: "flex flex-wrap gap-3 mb-3") do
          render_pick_badge(pick)
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
              TABLE_COLS.each do |col|
                th(class: "px-3 py-2 text-left font-medium whitespace-nowrap") { plain col }
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
      td(class: "px-3 py-2 font-mono whitespace-nowrap") { plain row[:expiration_date].to_s }
      td(class: "px-3 py-2 text-right")                  { plain row[:dte].to_s }
      td(class: "px-3 py-2 text-right font-semibold")    { plain fmt_price(row[:strike]) }
      td(class: "px-3 py-2 text-right")                  { plain fmt_decimal(row[:delta], 4) }
      td(class: "px-3 py-2 text-right font-semibold")    { plain fmt_int(row[:open_interest]) }
      td(class: "px-3 py-2 text-right")                  { plain fmt_int(row[:volume]) }
      td(class: "px-3 py-2") do
        div(class: "flex flex-col gap-0.5") do
          span(class: "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs " \
                       "#{style[:bg]} #{style[:text]} border #{style[:border]}") do
            div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{style[:dot]}")
            plain tier
          end
          if warn
            span(class: "text-orange-600 text-xs") { plain "⚠ 近期無成交" }
          end
        end
      end
      td(class: "px-3 py-2 text-right") { plain fmt_price(row[:bid]) }
      td(class: "px-3 py-2 text-right") { plain fmt_price(row[:ask]) }
      td(class: "px-3 py-2 text-right") { plain fmt_price(row[:mid]) }
      td(class: "px-3 py-2 text-right") { plain fmt_pct(row[:bid_ask_spread_pct]) }
      td(class: "px-3 py-2 text-right") { plain fmt_pct(row[:time_value_pct]) }
      td(class: "px-3 py-2 text-right") { plain fmt_pct(row[:iv]) }
      td(class: "px-3 py-2 text-right") { plain fmt_decimal(row[:vega], 4) }
      td(class: "px-3 py-2 text-right") { plain fmt_pct(row[:itm_probability]) }
    end
  end

  def render_flow_panel
    return unless @flow_panel&.dig(:status) == :ok

    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50 flex items-center justify-between") do
        div do
          h2(class: "text-sm font-semibold text-gray-700") { plain "Options Flow — 情緒參考，非排序依據" }
          p(class: "text-xs text-gray-400 mt-0.5") do
            plain "#{@flow_panel[:date]} · 前 20 大成交（依 Premium 降序）"
          end
        end
        render_premium_totals
      end

      render_highlighted if @flow_panel[:highlighted_trades]&.any?
      render_large_orders
    end
  end

  def render_premium_totals
    div(class: "flex gap-4 text-xs shrink-0") do
      div do
        span(class: "text-gray-400") { plain "Call " }
        span(class: "font-semibold text-green-700") { plain fmt_premium(@flow_panel[:call_premium_total]) }
      end
      div do
        span(class: "text-gray-400") { plain "Put " }
        span(class: "font-semibold text-red-700") { plain fmt_premium(@flow_panel[:put_premium_total]) }
      end
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
            FLOW_COLS.each do |col|
              th(class: "px-3 py-2 text-left font-medium whitespace-nowrap") { plain col }
            end
          end
        end
        tbody do
          orders.each { |t| render_flow_row(t) }
        end
      end
    end
  end

  def render_flow_row(t)
    dir   = (t[:direction] || "neutral").to_s
    ds    = DIR_STYLE[dir] || DIR_STYLE["neutral"]
    is_call = t[:option_type].to_s == "Call"
    tr(class: "border-t border-gray-100 hover:bg-gray-50") do
      td(class: "px-3 py-2 font-medium #{is_call ? 'text-green-700' : 'text-red-700'}") { plain t[:option_type].to_s }
      td(class: "px-3 py-2 text-right font-mono")  { plain fmt_price(t[:strike]) }
      td(class: "px-3 py-2 font-mono text-xs")     { plain t[:expires_at].to_s }
      td(class: "px-3 py-2 text-right")            { plain t[:dte].to_s }
      td(class: "px-3 py-2 text-right")            { plain fmt_decimal(t[:delta], 3) }
      td(class: "px-3 py-2 text-gray-500")         { plain t[:trade_condition].to_s }
      td(class: "px-3 py-2 text-right")            { plain fmt_int(t[:size]) }
      td(class: "px-3 py-2")                       { plain t[:side].to_s }
      td(class: "px-3 py-2 text-right font-semibold") { plain fmt_premium(t[:premium]) }
      td(class: "px-3 py-2") do
        div(class: "flex items-center gap-1") do
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
          if (inp) inp.addEventListener('input', function () { this.value = this.value.toUpperCase(); });

          form.addEventListener('submit', function (e) {
            e.preventDefault();
            var symbol = inp ? inp.value.trim().toUpperCase() : '';
            if (!symbol) return;

            btn.disabled = true;
            btn.textContent = '查詢中…';
            btn.classList.add('opacity-50', 'cursor-not-allowed');
            loading.classList.remove('hidden');
            loading.classList.add('flex');

            var csrfToken = document.querySelector('meta[name="csrf-token"]');
            var token = csrfToken ? csrfToken.content : '#{csrf}';

            fetch('/leaps/analyze', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
              body: JSON.stringify({ symbol: symbol })
            })
            .then(function (r) { return r.json(); })
            .then(function (data) {
              if (data.status === 'ready') {
                window.location.href = '/leaps?symbol=' + symbol;
                return;
              }
              if (data.status === 'cdp_offline') {
                window.location.href = '/leaps?symbol=' + symbol + '&job_status=error';
                return;
              }
              var jobId = data.job_id;
              if (!jobId) {
                window.location.href = '/leaps?symbol=' + symbol + '&job_status=error';
                return;
              }
              var attempts = 0;
              var pollInterval = setInterval(function () {
                attempts++;
                if (attempts > 240) {
                  clearInterval(pollInterval);
                  window.location.href = '/leaps?symbol=' + symbol + '&job_status=error';
                  return;
                }
                fetch('/leaps/status?job_id=' + jobId)
                  .then(function (r) { return r.json(); })
                  .then(function (s) {
                    if (s.status === 'pending' || s.status === 'not_found') return;
                    clearInterval(pollInterval);
                    window.location.href = '/leaps?symbol=' + symbol + '&job_status=' + s.status;
                  }).catch(function () {});
              }, 2500);
            }).catch(function () {
              window.location.href = '/leaps?symbol=' + symbol + '&job_status=error';
            });
          });
        })();
      JS
    end
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
