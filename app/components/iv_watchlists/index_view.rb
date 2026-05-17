# frozen_string_literal: true

class IvWatchlists::IndexView < ApplicationComponent
  GROUP_COLORS = {
    "index"     => "bg-blue-500/10 text-blue-300 border-blue-500/30",
    "leveraged" => "bg-orange-500/10 text-orange-300 border-orange-500/30",
    "macro"     => "bg-purple-500/10 text-purple-300 border-purple-500/30",
    "general"   => "bg-gray-500/10 text-gray-300 border-gray-500/30",
  }.freeze

  def initialize(grouped:, new_item:)
    @grouped  = grouped
    @new_item = new_item
  end

  def view_template
    div(class: "px-4 py-6") do
      div(class: "mb-8") do
        h1(class: "text-2xl font-semibold text-gray-900") { "IV Skew 追蹤清單" }
        p(class: "text-gray-600 text-sm mt-1") { "管理每日自動抓取 IV Skew 的美股標的" }
      end

      render AddSymbolForm.new

      if @grouped.empty?
        div(class: "text-center text-gray-500 py-12") { "清單為空，請先加入標的" }
      else
        div(class: "space-y-6 mt-8") do
          @grouped.each { |group_tag, items| render GroupSection.new(group_tag:, items:) }
        end
      end

      render StrategyGuide.new
    end
    render_scripts
  end

  private

  def render_scripts
    script do
      raw <<~JS.html_safe
        (function() {
          var csrf = function() {
            var m = document.querySelector('meta[name="csrf-token"]');
            return m ? m.content : '';
          };

          var ivCharts = {};
          var crosshairIdx = {};

          function makeCrosshair(rowId, isIv) {
            return {
              id: 'crosshair',
              afterEvent: function(chart, args) {
                var e = args.event;
                if (e.type === 'mousemove' && chart.tooltip._active && chart.tooltip._active.length) {
                  crosshairIdx[rowId] = chart.tooltip._active[0].index;
                  var pk = isIv ? (rowId + '-skew') : (rowId + '-iv');
                  var p  = ivCharts[pk];
                  if (p) p.draw();
                } else if (e.type === 'mouseout') {
                  crosshairIdx[rowId] = null;
                  var pk = isIv ? (rowId + '-skew') : (rowId + '-iv');
                  var p  = ivCharts[pk];
                  if (p) p.draw();
                }
              },
              afterDraw: function(chart) {
                var idx = crosshairIdx[rowId];
                if (idx == null) return;
                var meta = chart.getDatasetMeta(0);
                if (!meta || !meta.data || !meta.data[idx]) return;
                var x   = meta.data[idx].x;
                var ctx = chart.ctx;
                ctx.save();
                ctx.beginPath();
                ctx.moveTo(x, chart.chartArea.top);
                ctx.lineTo(x, chart.chartArea.bottom);
                ctx.setLineDash([4, 4]);
                ctx.strokeStyle = 'rgba(255,255,255,0.3)';
                ctx.lineWidth = 1;
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.restore();
              }
            };
          }

          async function loadIvChart(symbol, rowId, days) {
            var loadingEl = document.querySelector('[data-iv-chart-target="loading-' + rowId + '"]');
            if (loadingEl) loadingEl.classList.remove('hidden');

            if (ivCharts[rowId + '-iv'])   { ivCharts[rowId + '-iv'].destroy();   delete ivCharts[rowId + '-iv']; }
            if (ivCharts[rowId + '-skew']) { ivCharts[rowId + '-skew'].destroy(); delete ivCharts[rowId + '-skew']; }

            var res  = await fetch('/iv_watchlists/chart_data/' + symbol + '?days=' + days);
            var data = await res.json();

            if (loadingEl) loadingEl.classList.add('hidden');

            if (data.error === 'no_data') {
              var canvas = document.getElementById('chart-iv-' + rowId);
              if (!canvas) return;
              canvas.height = 80;
              var ctx = canvas.getContext('2d');
              ctx.fillStyle = '#888';
              ctx.font = '13px sans-serif';
              ctx.textAlign = 'center';
              ctx.fillText('尚無資料，請等待每日抓取累積', canvas.width / 2, 44);
              return;
            }

            var ivCanvas = document.getElementById('chart-iv-' + rowId);
            if (ivCanvas && typeof Chart !== 'undefined') {
              ivCharts[rowId + '-iv'] = new Chart(ivCanvas.getContext('2d'), {
                type: 'line',
                data: {
                  labels: data.labels,
                  datasets: [
                    { label: 'Put IV %',  data: data.put_iv,  borderColor: '#E85D5D', borderWidth: 1.5, pointRadius: 0, tension: 0.3, yAxisID: 'y'  },
                    { label: 'Call IV %', data: data.call_iv, borderColor: '#2ECC9A', borderWidth: 1.5, pointRadius: 0, tension: 0.3, yAxisID: 'y'  },
                    { label: '股價', data: data.price, borderColor: '#D4A017', borderWidth: 1.2, borderDash: [4,3], pointRadius: 0, tension: 0.3, yAxisID: 'y2' }
                  ]
                },
                options: {
                  responsive: true, maintainAspectRatio: false,
                  interaction: { mode: 'index', intersect: false },
                  plugins: {
                    legend: { labels: { color: '#aaa', font: { size: 10 } } },
                    tooltip: { backgroundColor: '#1a1a1a', titleColor: '#ccc', bodyColor: '#aaa' }
                  },
                  scales: {
                    x:  { ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } }, grid: { color: '#1e1e1e' } },
                    y:  { position: 'left',  ticks: { color: '#aaa', font: { size: 9 } }, grid: { color: '#1e1e1e' }, title: { display: true, text: 'IV %',  color: '#aaa', font: { size: 9 } } },
                    y2: { position: 'right', ticks: { color: '#D4A017', font: { size: 9 } }, grid: { drawOnChartArea: false }, title: { display: true, text: 'Price', color: '#D4A017', font: { size: 9 } } }
                  }
                },
                plugins: [makeCrosshair(rowId, true)]
              });
            }

            var skewCanvas = document.getElementById('chart-skew-' + rowId);
            if (skewCanvas && typeof Chart !== 'undefined') {
              var barColors = data.skew.map(function(v) {
                return v >= data.p75 ? 'rgba(224,64,176,0.75)' : 'rgba(85,119,170,0.75)';
              });
              ivCharts[rowId + '-skew'] = new Chart(skewCanvas.getContext('2d'), {
                type: 'bar',
                data: { labels: data.labels, datasets: [{ label: 'Skew %', data: data.skew, backgroundColor: barColors, borderWidth: 0 }] },
                options: {
                  responsive: true, maintainAspectRatio: false,
                  plugins: {
                    legend: { labels: { color: '#aaa', font: { size: 10 } } },
                    tooltip: {
                      backgroundColor: '#1a1a1a', titleColor: '#ccc', bodyColor: '#aaa',
                      callbacks: { afterBody: function(items) { return items[0] && items[0].raw >= data.p75 ? ['⚠️ 恐慌區（> 75th pct）'] : []; } }
                    }
                  },
                  scales: {
                    x: { ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } }, grid: { color: '#1e1e1e' } },
                    y: { ticks: { color: '#aaa', font: { size: 9 } }, grid: { color: '#1e1e1e' }, title: { display: true, text: 'Skew %', color: '#aaa', font: { size: 9 } } }
                  }
                },
                plugins: [makeCrosshair(rowId, false)]
              });
            }
          }

          document.addEventListener('click', async function(e) {
            var toggleBtn = e.target.closest('[data-action="click->watchlist#toggle:stop"]');
            if (toggleBtn) {
              e.stopPropagation();
              var res = await fetch(toggleBtn.dataset.url, {
                method: 'PATCH', headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
              });
              var d = await res.json();
              if (!d.success) return;
              toggleBtn.classList.toggle('bg-green-600', d.active);
              toggleBtn.classList.toggle('bg-gray-600', !d.active);
              var dot = toggleBtn.querySelector('span');
              dot.classList.toggle('left-5', d.active);
              dot.classList.toggle('left-1', !d.active);
              return;
            }

            var removeBtn = e.target.closest('[data-action="click->watchlist#remove:stop"]');
            if (removeBtn) {
              e.stopPropagation();
              if (!confirm('確定移除 ' + removeBtn.dataset.symbol + '？')) return;
              var res = await fetch(removeBtn.dataset.url, {
                method: 'DELETE', headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
              });
              var d = await res.json();
              if (d.success) {
                var row = document.getElementById('watchlist-row-' + removeBtn.dataset.id);
                if (row) row.remove();
              }
              return;
            }

            var chartRow = e.target.closest('[data-action="click->iv-chart#toggle"]');
            if (chartRow) {
              var symbol = chartRow.dataset.symbol;
              var rowId  = chartRow.dataset.rowId;
              var panel  = document.getElementById('chart-panel-' + rowId);
              var arrow  = document.querySelector('[data-iv-chart-target="arrow-' + rowId + '"]');
              if (!panel) return;
              var isOpen = !panel.classList.contains('hidden');
              if (isOpen) {
                panel.classList.add('hidden');
                if (arrow) arrow.style.transform = '';
              } else {
                panel.classList.remove('hidden');
                if (arrow) arrow.style.transform = 'rotate(90deg)';
                await loadIvChart(symbol, rowId, 90);
              }
              return;
            }

            var dayBtn = e.target.closest('[data-action="click->iv-chart#changeDays"]');
            if (dayBtn) {
              var symbol = dayBtn.dataset.symbol;
              var rowId  = dayBtn.dataset.rowId;
              var panel  = document.getElementById('chart-panel-' + rowId);
              panel.querySelectorAll('[data-action="click->iv-chart#changeDays"]').forEach(function(btn) {
                btn.classList.remove('bg-blue-600','border-blue-500','text-white');
                btn.classList.add('bg-gray-800','border-gray-600','text-gray-400');
              });
              dayBtn.classList.add('bg-blue-600','border-blue-500','text-white');
              dayBtn.classList.remove('bg-gray-800','border-gray-600','text-gray-400');
              await loadIvChart(symbol, rowId, parseInt(dayBtn.dataset.days));
              return;
            }

            var chip = e.target.closest('[data-action="click->watchlist-form#quickAdd"]');
            if (chip) {
              var input = document.querySelector('[data-watchlist-form-target="input"]');
              if (input) { input.value = chip.dataset.symbol; input.focus(); }
            }
          });
        })();
      JS
    end
  end

  class AddSymbolForm < ApplicationComponent
    QUICK_SYMBOLS = %w[AAPL NVDA TSLA MSFT AMZN META GOOGL AMD].freeze

    def view_template
      div(class: "bg-gray-900 border border-gray-700 rounded-xl p-6") do
        h2(class: "text-sm font-medium text-gray-300 mb-4") { "新增標的" }
        form(action: "/iv_watchlists", method: "post", class: "flex flex-col sm:flex-row gap-3") do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          input(
            type: "text", name: "iv_watchlist[symbol]",
            placeholder: "美股代號，例如 NVDA", maxlength: "10", autocomplete: "off",
            class: "flex-1 bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-500 uppercase focus:outline-none focus:border-blue-500 transition-colors",
            data: { watchlist_form_target: "input" }
          )
          select(
            name: "iv_watchlist[group_tag]",
            class: "bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-gray-300 focus:outline-none focus:border-blue-500 transition-colors"
          ) do
            IvWatchlist::GROUP_TAGS.each { |tag| option(value: tag) { tag.capitalize } }
          end
          button(
            type: "submit",
            class: "bg-blue-600 hover:bg-blue-500 text-white font-medium rounded-lg px-5 py-2 transition-colors whitespace-nowrap"
          ) { "+ 加入" }
        end
        div(class: "mt-4") do
          p(class: "text-xs text-gray-500 mb-2") { "快速加入：" }
          div(class: "flex flex-wrap gap-2") do
            QUICK_SYMBOLS.each do |sym|
              button(
                type: "button",
                class: "px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 border border-gray-600 rounded-full transition-colors cursor-pointer",
                data: { symbol: sym, action: "click->watchlist-form#quickAdd" }
              ) { sym }
            end
          end
        end
      end
    end
  end

  class GroupSection < ApplicationComponent
    def initialize(group_tag:, items:)
      @group_tag = group_tag
      @items     = items
    end

    def view_template
      div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
        div(class: "flex items-center gap-3 px-5 py-3 border-b border-gray-700") do
          span(
            class: "text-xs font-medium px-2 py-0.5 rounded border #{IvWatchlists::IndexView::GROUP_COLORS.fetch(@group_tag, IvWatchlists::IndexView::GROUP_COLORS['general'])}"
          ) { @group_tag.upcase }
          span(class: "text-gray-400 text-sm") { "#{@items.size} 個標的" }
        end
        div(class: "divide-y divide-gray-800") do
          @items.each { |item| render SymbolRow.new(item:) }
        end
      end
    end
  end

  class SymbolRow < ApplicationComponent
    def initialize(item:)
      @item = item
    end

    def view_template
      div(id: "watchlist-row-#{@item.id}", class: "border-b border-gray-800 last:border-0") do
        div(
          class: "flex items-center justify-between px-5 py-3 hover:bg-gray-800/50 transition-colors cursor-pointer select-none",
          data:  { action: "click->iv-chart#toggle", symbol: @item.symbol, row_id: @item.id }
        ) do
          div(class: "flex items-center gap-3") do
            span(class: "text-gray-500 text-xs transition-transform duration-200", data: { iv_chart_target: "arrow-#{@item.id}" }) { "▶" }
            span(class: "text-white font-mono font-medium text-sm") { @item.symbol }
            span(class: "text-gray-500 text-xs") { "加入於 #{@item.created_at.strftime('%Y/%m/%d')}" }
          end
          div(class: "flex items-center gap-3") do
            button(
              type: "button",
              class: "relative w-9 h-5 rounded-full transition-colors #{@item.active? ? 'bg-green-600' : 'bg-gray-600'}",
              data:  { action: "click->watchlist#toggle:stop", url: "/iv_watchlists/#{@item.id}/toggle", id: @item.id },
              title: @item.active? ? "點擊停用" : "點擊啟用"
            ) do
              span(class: "absolute top-1 w-3 h-3 bg-white rounded-full transition-all #{@item.active? ? 'left-5' : 'left-1'}")
            end
            button(
              type: "button",
              class: "text-gray-600 hover:text-red-400 transition-colors px-1",
              data:  { action: "click->watchlist#remove:stop", url: "/iv_watchlists/#{@item.id}", symbol: @item.symbol, id: @item.id },
              title: "移除 #{@item.symbol}"
            ) { "✕" }
          end
        end

        div(id: "chart-panel-#{@item.id}", class: "hidden px-5 pb-5 pt-2 bg-gray-950") do
          div(class: "flex gap-2 mb-3") do
            [7, 30, 60, 90, 180].each do |d|
              button(
                type: "button",
                class: "px-3 py-1 text-xs rounded border transition-colors #{d == 90 ? 'bg-blue-600 border-blue-500 text-white' : 'bg-gray-800 border-gray-600 text-gray-400 hover:text-white'}",
                data:  { action: "click->iv-chart#changeDays", symbol: @item.symbol, days: d, row_id: @item.id }
              ) { "#{d}天" }
            end
          end
          div(class: "text-gray-500 text-sm text-center py-4 hidden", data: { iv_chart_target: "loading-#{@item.id}" }) { "載入中..." }
          div(class: "relative", style: "height:280px") { canvas(id: "chart-iv-#{@item.id}") }
          div(class: "relative mt-3", style: "height:120px") { canvas(id: "chart-skew-#{@item.id}") }
          div(class: "flex gap-4 mt-2 text-xs text-gray-500") do
            span { "🔴 Put IV" }
            span { "🟢 Call IV" }
            span { "🟡 股價（右軸）" }
            span { "🟣 Skew > 75th pct = 恐慌區" }
          end

          div(class: "mt-4 bg-gray-900 border border-gray-700/50 rounded-lg px-4 py-3") do
            p(class: "text-xs font-medium text-gray-400 mb-2") { "📖 底部訊號閱讀順序" }
            div(class: "space-y-1.5 text-xs text-gray-500") do
              div(class: "flex items-start gap-2") do
                span(class: "text-gray-600 font-mono flex-shrink-0") { "1." }
                span { "📉 黃虛線（股價）持續往下" }
              end
              div(class: "flex items-start gap-2") do
                span(class: "text-gray-600 font-mono flex-shrink-0") { "2." }
                span { "🔵→🩷 柱子從藍色變桃紅色 → 進入警戒，不要動作" }
              end
              div(class: "flex items-start gap-2") do
                span(class: "text-gray-600 font-mono flex-shrink-0") { "3." }
                span { "⏳ 桃紅色持續 2～3 根 → 恐慌累積期，繼續觀望" }
              end
              div(class: "flex items-start gap-2") do
                span(class: "text-green-500 font-mono flex-shrink-0") { "4." }
                span(class: "text-green-400 font-medium") { "📏 下一根桃紅柱明顯縮短 ← 底部訊號，恐慌釋放完畢，反彈即將來臨" }
              end
            end
          end
        end
      end
    end
  end
  # ── 策略說明 ────────────────────────────────────────────
  class StrategyGuide < ApplicationComponent
    SIGNAL_STEPS = [
      { icon: "📉", label: "股價持續下跌", desc: "黃虛線（股價右軸）持續往下，市場進入恐慌模式" },
      { icon: "🔵→🩷", label: "柱子從藍色變桃紅色", desc: "Skew 飆升超過 75th pct，市場瘋狂買 Put 護盤，進入警戒區" },
      { icon: "⏳", label: "桃紅色持續 2～3 根", desc: "恐慌情緒累積期，繼續觀望，不要急著進場" },
      { icon: "📏", label: "下一根桃紅柱明顯縮短", desc: "← 底部訊號：Skew 開始收斂，恐慌釋放完畢，反彈即將來臨" },
    ].freeze

    WHEEL_ROWS = [
      { signal: "Skew 開始飆高（藍→桃紅）",      meaning: "QQQ 下跌中，SQQQ 上漲",           action: "不要新開 CSP，持倉觀望",         color: "text-yellow-400" },
      { signal: "Skew 持續桃紅 2～3 根",           meaning: "恐慌累積期",                       action: "繼續觀望，不動",                 color: "text-orange-400" },
      { signal: "桃紅後首根明顯縮短",              meaning: "底部訊號，QQQ 即將反彈，SQQQ 頂部臨近", action: "準備進場評估 SQQQ CSP",      color: "text-green-400" },
      { signal: "Skew 回落至藍色、收窄",           meaning: "QQQ 回升確認",                     action: "可重新開 SQQQ CSP 收 Premium", color: "text-blue-400" },
    ].freeze

    def view_template
      div(class: "mt-8 space-y-4") do
        render_signal_guide
        render_wheel_table
      end
    end

    private

    def render_signal_guide
      div(class: "bg-gray-900 border border-gray-700 rounded-xl p-6") do
        div(class: "flex items-center gap-2 mb-5") do
          span(class: "text-lg") { "📊" }
          h2(class: "text-sm font-semibold text-gray-200") { "Skew 底部訊號閱讀順序" }
          span(class: "text-xs text-gray-500 ml-2") { "（依序觀察 4 個步驟）" }
        end

        div(class: "space-y-3") do
          SIGNAL_STEPS.each_with_index do |step, i|
            div(class: "flex gap-4 items-start") do
              div(class: "flex flex-col items-center flex-shrink-0") do
                div(class: "w-7 h-7 rounded-full bg-gray-800 border border-gray-600 flex items-center justify-center text-xs font-bold text-gray-300") { (i + 1).to_s }
                div(class: "w-px h-4 bg-gray-700 mt-1") unless i == SIGNAL_STEPS.size - 1
              end
              div(class: "pb-2") do
                div(class: "flex items-center gap-2 mb-0.5") do
                  span(class: "text-base") { step[:icon] }
                  span(class: "#{ i == 3 ? 'text-green-300 font-semibold' : 'text-gray-200' } text-sm") { step[:label] }
                end
                p(class: "text-xs text-gray-500 leading-relaxed") { step[:desc] }
              end
            end
          end
        end
      end
    end

    def render_wheel_table
      div(class: "bg-gray-900 border border-gray-700 rounded-xl overflow-hidden") do
        div(class: "flex items-center gap-2 px-6 py-4 border-b border-gray-700") do
          span(class: "text-lg") { "🎡" }
          h2(class: "text-sm font-semibold text-gray-200") { "SQQQ Wheel 策略對照表" }
          span(class: "text-xs text-gray-500 ml-2") { "Put/Call Skew 訊號 → 操作含意" }
        end

        div(class: "overflow-x-auto") do
          table(class: "w-full text-xs") do
            thead do
              tr(class: "bg-gray-800/60") do
                th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "觀察到的現象" }
                th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "市場含意" }
                th(class: "px-5 py-3 text-left text-gray-400 font-medium w-1/3") { "操作含意" }
              end
            end
            tbody do
              WHEEL_ROWS.each_with_index do |row, i|
                tr(class: "border-t border-gray-800 #{ i == 2 ? 'bg-green-950/30' : '' }") do
                  td(class: "px-5 py-3 text-gray-300 font-mono leading-relaxed") { row[:signal] }
                  td(class: "px-5 py-3 text-gray-400 leading-relaxed") { row[:meaning] }
                  td(class: "px-5 py-3 #{row[:color]} font-medium leading-relaxed") { row[:action] }
                end
              end
            end
          end
        end

        div(class: "px-6 py-3 bg-gray-800/40 border-t border-gray-700") do
          p(class: "text-xs text-gray-500") do
            plain("💡 CSP = Cash-Secured Put｜收 Premium 的前提是：Skew 已確認收斂，股價反彈開始。桃紅柱子期間不進場。")
          end
        end
      end
    end
  end

end
