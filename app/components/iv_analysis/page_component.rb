# frozen_string_literal: true

class IvAnalysis::PageComponent < ApplicationComponent
  def view_template
    div do
      div(class: "flex items-center justify-between mb-6") do
        div do
          h1(class: "text-xl font-bold text-gray-900") { plain "期權 IV 分析" }
          p(class: "text-sm text-gray-500 mt-0.5") { plain "IV Rank · IV Percentile · ATM IV 歷史追蹤" }
        end
      end

      render IvAnalysis::QueryFormComponent.new
      render IvAnalysis::ResultComponent.new
      render IvAnalysis::WatchlistComponent.new
      render IvAnalysis::EducationComponent.new
    end

    render_script
  end

  private

  def render_script
    script do
      raw <<~JS.html_safe
        (function () {
          'use strict';

          // ── Call/Put toggle ───────────────────────────────────────────
          var callBtn   = document.getElementById('iv-type-call');
          var putBtn    = document.getElementById('iv-type-put');
          var typeInput = document.getElementById('iv-option-type');

          var ACTIVE   = 'flex-1 py-2 bg-blue-600 text-white font-medium transition-colors';
          var INACTIVE = 'flex-1 py-2 bg-white text-gray-600 hover:bg-gray-50 font-medium transition-colors';

          callBtn.addEventListener('click', function () {
            callBtn.className = ACTIVE;
            putBtn.className  = INACTIVE;
            typeInput.value   = 'call';
          });
          putBtn.addEventListener('click', function () {
            putBtn.className  = ACTIVE;
            callBtn.className = INACTIVE;
            typeInput.value   = 'put';
          });

          // ── Form submit ───────────────────────────────────────────────
          var form      = document.getElementById('iv-analysis-form');
          var submitBtn = document.getElementById('iv-submit-btn');
          var errorMsg  = document.getElementById('iv-error-msg');

          form.addEventListener('submit', function (e) {
            e.preventDefault();
            var fd = new FormData(form);
            var payload = {
              ticker:      fd.get('ticker').toUpperCase().trim(),
              strike:      parseFloat(fd.get('strike')),
              expiry_date: fd.get('expiry_date'),
              option_type: fd.get('option_type')
            };

            errorMsg.classList.add('hidden');
            errorMsg.textContent  = '';
            submitBtn.disabled    = true;
            submitBtn.textContent = '查詢中…';

            fetch('/api/iv_analysis', {
              method:  'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
              },
              body: JSON.stringify(payload)
            })
              .then(function (res) {
                return res.json().then(function (data) { return { ok: res.ok, data: data }; });
              })
              .then(function (r) {
                if (!r.ok) throw new Error(r.data.error || '查詢失敗');
                renderResult(r.data);
                loadWatchlist();
              })
              .catch(function (err) {
                errorMsg.textContent = err.message;
                errorMsg.classList.remove('hidden');
              })
              .finally(function () {
                submitBtn.disabled    = false;
                submitBtn.textContent = '查詢 IV';
              });
          });

          // ── Render result ─────────────────────────────────────────────
          function renderResult(d) {
            document.getElementById('iv-result-section').classList.remove('hidden');
            document.getElementById('iv-result-ticker').textContent =
              d.ticker + ' ' + d.option_type.toUpperCase() + ' ' + d.strike + ' ' + d.expiry_date;

            var snapWarn = document.getElementById('iv-snap-warning');
            if (d.snap_notice) {
              snapWarn.textContent = d.snap_notice;
              snapWarn.classList.remove('hidden');
            } else {
              snapWarn.classList.add('hidden');
              snapWarn.textContent = '';
            }
            document.getElementById('iv-result-time').textContent =
              new Date(d.queried_at).toLocaleString('zh-TW');

            document.getElementById('iv-card-price').textContent =
              '$' + parseFloat(d.current_price).toFixed(2);

            var deltaEl = document.getElementById('iv-card-delta');
            var delta   = parseFloat(d.delta);
            deltaEl.textContent = delta.toFixed(4);
            deltaEl.className = 'text-lg font-bold ' +
              (delta > 0.5 ? 'text-blue-600' : delta >= 0.3 ? 'text-green-600' : 'text-gray-500');

            document.getElementById('iv-card-iv').textContent =
              (parseFloat(d.iv) * 100).toFixed(2) + '%';

            renderIvrCell('iv-ivr-1y', d.ivr_1y);
            renderIvrCell('iv-ivr-2y', d.ivr_2y);
            renderStatCell('iv-ivp-1y', d.ivp_1y);
            renderStatCell('iv-ivp-2y', d.ivp_2y);

            renderQualityBanner(d.data_quality, d.available_days, d.notice);
            renderConclusion(d);
          }

          function renderIvrCell(id, val) {
            var el = document.getElementById(id);
            if (val === null || val === undefined) {
              el.textContent = '—';
              el.className   = 'py-2 text-center text-gray-400';
              return;
            }
            var v = parseFloat(val);
            el.textContent = v.toFixed(1) + '%';
            if (v < 20)      el.className = 'py-2 text-center font-semibold text-green-600';
            else if (v > 80) el.className = 'py-2 text-center font-semibold text-red-600';
            else             el.className = 'py-2 text-center font-medium text-gray-700';
          }

          function renderStatCell(id, val) {
            var el = document.getElementById(id);
            if (val === null || val === undefined) {
              el.textContent = '—';
              el.className   = 'py-2 text-center text-gray-400';
            } else {
              el.textContent = parseFloat(val).toFixed(1) + '%';
              el.className   = 'py-2 text-center font-medium text-gray-700';
            }
          }

          var BANNER_STYLES = {
            insufficient: 'bg-yellow-50 border border-yellow-200 text-yellow-800',
            limited:      'bg-gray-50  border border-gray-200  text-gray-600',
            good:         'bg-blue-50  border border-blue-200  text-blue-800',
            excellent:    'bg-green-50 border border-green-200 text-green-800'
          };
          var BANNER_TEXT = {
            insufficient: function (n) { return '⚠️ 資料累積不足 30 天（現有 ' + n + ' 天），IVR/IVP 尚不可靠'; },
            limited:      function (n) { return '📊 資料累積中（' + n + ' 天），建議等待更多歷史資料'; },
            good:         function (n) { return '✅ 資料品質良好（' + n + ' 天）'; },
            excellent:    function (n) { return '✅ 資料充足（' + n + ' 天），統計結果可信'; }
          };

          function renderQualityBanner(quality, days, notice) {
            var el  = document.getElementById('iv-quality-banner');
            var txt = (BANNER_TEXT[quality] || function (n) { return n + ' 天'; })(days);
            if (notice && quality !== 'insufficient') txt += '　' + notice;
            el.textContent = txt;
            el.className   = 'mb-4 px-4 py-2.5 rounded-lg text-sm ' + (BANNER_STYLES[quality] || '');
            el.classList.remove('hidden');
          }

          function renderConclusion(d) {
            var el     = document.getElementById('iv-conclusion');
            var ivr_1y = d.ivr_1y !== null && d.ivr_1y !== undefined ? parseFloat(d.ivr_1y) : null;
            var ivr_2y = d.ivr_2y !== null && d.ivr_2y !== undefined ? parseFloat(d.ivr_2y) : null;
            var text, cls;

            if (ivr_1y === null) {
              text = 'IV 歷史資料不足，暫無信號';
              cls  = 'mt-4 px-4 py-3 rounded-lg text-sm bg-gray-50 text-gray-500';
            } else if (ivr_1y < 20 && ivr_2y !== null && ivr_2y < 20) {
              text = '✅ IV 同時處於一年及兩年低點，買入期權信號較強';
              cls  = 'mt-4 px-4 py-3 rounded-lg text-sm bg-green-50 text-green-800 font-medium';
            } else if (ivr_1y < 20) {
              text = '✅ IV 處於一年低點，買入期權勝算較高';
              cls  = 'mt-4 px-4 py-3 rounded-lg text-sm bg-green-50 text-green-700';
            } else if (ivr_1y > 80) {
              text = '⚠️ IV 偏高，Vega 風險大，考慮賣方策略';
              cls  = 'mt-4 px-4 py-3 rounded-lg text-sm bg-red-50 text-red-700';
            } else {
              text = 'IV 處於中性區間（IVR ' + ivr_1y.toFixed(1) + '%）';
              cls  = 'mt-4 px-4 py-3 rounded-lg text-sm bg-gray-50 text-gray-600';
            }
            el.textContent = text;
            el.className   = cls;
            el.classList.remove('hidden');
          }

          // ── Watchlist ─────────────────────────────────────────────────
          var QUALITY_BADGE = {
            insufficient: 'bg-yellow-100 text-yellow-700',
            limited:      'bg-gray-100 text-gray-600',
            good:         'bg-blue-100 text-blue-700',
            excellent:    'bg-green-100 text-green-700'
          };
          var QUALITY_LABEL = {
            insufficient: '累積中',
            limited:      '有限',
            good:         '良好',
            excellent:    '充足'
          };

          function loadWatchlist() {
            fetch('/api/iv_analysis/watchlist')
              .then(function (r) { return r.json(); })
              .then(function (data) { renderWatchlist(data.watchlist); })
              .catch(function () {});
          }

          function recalcRow(ticker) {
            var row = document.getElementById('wl-row-' + ticker);
            if (!row) return;
            var S     = parseFloat(row.dataset.price  || '0');
            var sigma = parseFloat(row.dataset.iv     || '0');
            var type  = row.dataset.otype || 'call';
            var K     = parseFloat(row.querySelector('.wl-strike-input').value  || '0');
            var expiry= row.querySelector('.wl-expiry-input').value;
            var days  = expiry ? Math.max(0, (new Date(expiry) - new Date()) / 86400000) : 0;
            var T     = days / 365;
            var intrinsic = type === 'call' ? Math.max(0, S - K) : Math.max(0, K - S);
            var timeVal   = T > 0 ? 0.4 * S * sigma * Math.sqrt(T) : 0;
            var iEl = row.querySelector('.wl-intrinsic-val');
            var tEl = row.querySelector('.wl-time-val');
            if (iEl) {
              iEl.textContent = '$' + intrinsic.toFixed(2);
              iEl.className   = 'wl-intrinsic-val font-mono text-sm ' + (intrinsic > 0 ? 'text-blue-600' : 'text-gray-400');
            }
            if (tEl) tEl.textContent = '$' + timeVal.toFixed(2);
          }

          function ivrCell(val) {
            if (val === null || val === undefined) return '<td class="px-4 py-3 text-right text-gray-300">—</td>';
            var v = parseFloat(val);
            var cls = v < 20 ? 'font-semibold text-green-600' : v > 80 ? 'font-semibold text-red-600' : 'text-gray-700';
            return '<td class="px-4 py-3 text-right"><span class="font-mono text-sm ' + cls + '">' + v.toFixed(1) + '%</span></td>';
          }
          function ivpCell(val) {
            if (val === null || val === undefined) return '<td class="px-4 py-3 text-right text-gray-300">—</td>';
            return '<td class="px-4 py-3 text-right"><span class="font-mono text-sm text-gray-600">' + parseFloat(val).toFixed(1) + '%</span></td>';
          }

          function renderWatchlist(list) {
            var tbody = document.getElementById('iv-watchlist-body');
            if (!list || list.length === 0) {
              tbody.innerHTML = '<tr><td colspan="14" class="px-4 py-8 text-center text-sm text-gray-400">尚無追蹤中的股票</td></tr>';
              return;
            }
            tbody.innerHTML = list.map(function (item) {
              var iv    = item.latest_atm_iv
                ? (parseFloat(item.latest_atm_iv) * 100).toFixed(2) + '%' : '—';
              var badge = QUALITY_BADGE[item.data_quality] || 'bg-gray-100 text-gray-500';
              var label = QUALITY_LABEL[item.data_quality] || item.data_quality;
              var ts    = item.last_fetched_at
                ? new Date(item.last_fetched_at).toLocaleDateString('zh-TW') : '—';

              var intrinsicCell, timeCell;
              if (item.intrinsic_value !== null && item.intrinsic_value !== undefined) {
                var liveTag = item.is_live
                  ? '<span title="即時報價" style="font-size:0.6rem;vertical-align:middle;margin-left:3px">🟢</span>'
                  : '<span title="使用快取值，點重新整理取得即時數據" style="font-size:0.6rem;vertical-align:middle;margin-left:3px">⚪</span>';
                var sub = item.query_label
                  ? '<br><span style="font-size:0.65rem;color:#9ca3af">' + item.query_label + liveTag + '</span>'
                  : '';
                intrinsicCell = '<td class="px-4 py-3 text-right">' +
                  '<span class="wl-intrinsic-val font-mono text-sm ' + (item.intrinsic_value > 0 ? 'text-blue-600' : 'text-gray-400') + '">' +
                  '$' + parseFloat(item.intrinsic_value).toFixed(2) + '</span>' + sub + '</td>';
                timeCell = '<td class="px-4 py-3 text-right">' +
                  '<span class="wl-time-val font-mono text-sm text-orange-500">$' +
                  parseFloat(item.time_value).toFixed(2) + '</span>' + sub + '</td>';
              } else {
                intrinsicCell = '<td class="px-4 py-3 text-right text-gray-300 text-xs">尚無查詢</td>';
                timeCell      = '<td class="px-4 py-3 text-right text-gray-300 text-xs">—</td>';
              }

              var typeTag = item.option_type
                ? '<span class="inline-block px-1.5 py-0.5 rounded text-xs font-bold mr-1.5 ' + (item.option_type === 'call' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700') + '">' + item.option_type.toUpperCase() + '</span>'
                : '';
              var strikeCell = item.strike != null
                ? '<td class="px-3 py-2 text-right">' + typeTag + '<input type="number" class="wl-strike-input font-mono text-sm text-gray-700 w-20 text-right border border-gray-200 rounded px-1.5 py-0.5 hover:border-blue-400 focus:border-blue-500 focus:outline-none" value="' + parseFloat(item.strike).toFixed(1) + '" step="0.5" data-ticker="' + item.ticker + '"></td>'
                : '<td class="px-3 py-2 text-right text-gray-300">—</td>';
              var expiryCell = item.expiry_date != null
                ? '<td class="px-3 py-2 text-right"><input type="date" class="wl-expiry-input text-sm text-gray-700 border border-gray-200 rounded px-1.5 py-0.5 hover:border-blue-400 focus:border-blue-500 focus:outline-none" value="' + item.expiry_date + '" data-ticker="' + item.ticker + '"></td>'
                : '<td class="px-3 py-2 text-right text-gray-300">—</td>';

              return '<tr class="border-b border-gray-50 hover:bg-gray-50 transition-colors" id="wl-row-' + item.ticker + '" data-price="' + (item.live_price || '') + '" data-iv="' + (item.live_iv || '') + '" data-otype="' + (item.option_type || 'call') + '">' +
                '<td class="px-4 py-3 font-semibold text-gray-800">' + item.ticker + '</td>' +
                '<td class="px-4 py-3 text-right font-mono text-gray-700">' + iv + '</td>' +
                ivrCell(item.ivr_1y) +
                ivpCell(item.ivp_1y) +
                ivrCell(item.ivr_2y) +
                ivpCell(item.ivp_2y) +
                strikeCell +
                expiryCell +
                intrinsicCell +
                timeCell +
                '<td class="px-4 py-3 text-right text-gray-600">' + item.available_days + ' 天</td>' +
                '<td class="px-4 py-3 text-center"><span class="inline-block px-2 py-0.5 rounded-full text-xs font-medium ' + badge + '">' + label + '</span></td>' +
                '<td class="px-4 py-3 text-right text-gray-400 text-xs">' + ts + '</td>' +
                '<td class="px-4 py-3 text-center">' +
                  '<button class="wl-remove-btn text-xs text-red-400 hover:text-red-600 transition-colors" data-ticker="' + item.ticker + '">移除</button>' +
                '</td></tr>';
            }).join('');
          }

          document.getElementById('iv-watchlist-refresh')
            .addEventListener('click', loadWatchlist);

          document.addEventListener('input', function (e) {
            var el = e.target;
            if (el.classList.contains('wl-strike-input') || el.classList.contains('wl-expiry-input')) {
              recalcRow(el.dataset.ticker);
            }
          });

          document.addEventListener('click', function (e) {
            var btn = e.target.closest('.wl-remove-btn');
            if (!btn) return;
            var ticker = btn.dataset.ticker;
            fetch('/api/iv_analysis/watchlist/' + ticker, {
              method:  'DELETE',
              headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
            })
              .then(function () {
                var row = document.getElementById('wl-row-' + ticker);
                if (!row) return;
                row.style.transition = 'opacity 0.3s';
                row.style.opacity    = '0';
                setTimeout(function () { row.remove(); }, 300);
              })
              .catch(function () {});
          });

          loadWatchlist();
        })();
      JS
    end
  end
end
