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

      render IvSkewExplainer.new
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
          function makeCrosshair(rowId) {
            return {
              id: 'crosshair',
              afterEvent: function(chart, args) {
                var e    = args.event;
                var line = document.getElementById('ch-line-' + rowId);
                if (!line) return;
                if (e.type === 'mousemove' && chart.tooltip._active && chart.tooltip._active.length) {
                  var idx  = chart.tooltip._active[0].index;
                  var ivC  = ivCharts[rowId + '-iv'];
                  if (!ivC) return;
                  var meta = ivC.getDatasetMeta(0);
                  if (!meta.data[idx]) return;
                  var cRect = ivC.canvas.getBoundingClientRect();
                  var wRect = line.parentElement.getBoundingClientRect();
                  line.style.left    = (meta.data[idx].x + cRect.left - wRect.left) + 'px';
                  line.style.display = 'block';
                } else if (e.type === 'mouseout') {
                  line.style.display = 'none';
                }
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

            var makeXTicks = function(maxLabels, intraday) {
              return {
                color: '#666', autoSkip: false,
                maxRotation: intraday ? 45 : 0, minRotation: 0,
                font: { size: 9 },
                callback: function(value, index, ticks) {
                  var n = ticks.length;
                  var step = Math.max(1, Math.floor(n / maxLabels));
                  if (index === 0 || index === n - 1 || index % step === 0) return this.getLabelForValue(value);
                  return null;
                }
              };
            };
            var xAxisCfg = data.intraday
              ? { ticks: makeXTicks(14, true),  grid: { color: '#1e1e1e' } }
              : { ticks: makeXTicks(8,  false), grid: { color: '#1e1e1e' } };

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
                    x:  xAxisCfg,
                    y:  { position: 'left',  ticks: { color: '#aaa', font: { size: 9 } }, grid: { color: '#1e1e1e' }, title: { display: true, text: 'IV %',  color: '#aaa', font: { size: 9 } } },
                    y2: { position: 'right', ticks: { color: '#D4A017', font: { size: 9 } }, grid: { drawOnChartArea: false }, title: { display: true, text: 'Price', color: '#D4A017', font: { size: 9 } } }
                  }
                },
                plugins: [makeCrosshair(rowId)]
              });
            }

            // 讀取 IV 圖右軸實際寬度，作為 Skew 圖右側 padding，確保兩圖 chartArea 對齊
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
                      callbacks: { afterBody: function(items) { return items[0] && items[0].raw >= data.p75 ? ['\u26a0\ufe0f 恐慌區（> 75th pct）'] : []; } }
                    }
                  },
                  scales: {
                    x: xAxisCfg,
                    y: { ticks: { color: '#aaa', font: { size: 9 } }, grid: { color: '#1e1e1e' }, title: { display: true, text: 'Skew %', color: '#aaa', font: { size: 9 } } },
                    y2: {
                      position: 'right',
                      display: true,
                      afterFit: function(scale) {
                        var ivC = ivCharts[rowId + '-iv'];
                        if (ivC && ivC.scales && ivC.scales['y2']) {
                          scale.width = ivC.scales['y2'].width;
                        }
                      },
                      ticks: { display: false, maxTicksLimit: 0 },
                      grid: { display: false },
                      border: { display: false },
                      title: { display: false }
                    }
                  }
                },
                plugins: [makeCrosshair(rowId)]
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

end
