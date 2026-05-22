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

      render IvAnalysis::DashboardComponent.new
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

          // ── Expiry dropdown dynamic load ──────────────────────────
          var tickerInput  = document.getElementById('iv-ticker');
          var expirySelect = document.getElementById('iv-expiry');

          function buildExpiryOptions(expirations, weeklyCount) {
            expirySelect.innerHTML = '';
            var near = expirations.slice(0, weeklyCount);
            var far  = expirations.slice(weeklyCount);

            function addGroup(label, dates) {
              if (!dates.length) return;
              var grp = document.createElement('optgroup');
              grp.label = label;
              dates.forEach(function(d, i) {
                var opt = document.createElement('option');
                opt.value = d;
                opt.textContent = d.replace(/-/g, '/');
                if (i === 0 && label.indexOf('近期') >= 0) opt.selected = true;
                grp.appendChild(opt);
              });
              expirySelect.appendChild(grp);
            }

            addGroup('近期（週選）', near);
            addGroup('月選 / LEAPS', far);
          }

          function loadExpirations(ticker) {
            if (!ticker) return;
            fetch('/api/iv_analysis/expirations?ticker=' + encodeURIComponent(ticker))
              .then(function(r) { return r.json(); })
              .then(function(data) {
                if (data.expirations && data.expirations.length) {
                  buildExpiryOptions(data.expirations, data.weekly_count || 6);
                }
              })
              .catch(function() {});
          }

          tickerInput.addEventListener('blur', function() {
            var t = tickerInput.value.toUpperCase().trim();
            if (t.length >= 1) loadExpirations(t);
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

            document.getElementById('iv-card-dte').textContent =
              (d.dte !== null && d.dte !== undefined) ? d.dte + ' 天' : '—';

            var atmEl = document.getElementById('iv-card-atm');
            if (d.atm_iv !== null && d.atm_iv !== undefined) {
              atmEl.textContent = (parseFloat(d.atm_iv) * 100).toFixed(2) + '%';
            } else {
              atmEl.textContent = '—%';
            }

            var hvEl  = document.getElementById('iv-card-hv');
            var hvWin = document.getElementById('iv-card-hv-window');
            if (d.hv_dte !== null && d.hv_dte !== undefined) {
              var hvPct = parseFloat(d.hv_dte) * 100;
              var atm   = d.atm_iv !== null ? parseFloat(d.atm_iv) * 100 : null;
              hvEl.textContent = hvPct.toFixed(2) + '%';
              hvEl.className = 'text-lg font-bold ' +
                (atm !== null && hvPct > atm + 5 ? 'text-green-600' :
                 atm !== null && hvPct < atm - 5 ? 'text-orange-500' : 'text-gray-800');
              if (hvWin && d.hv_window) hvWin.textContent = d.hv_window;
            } else {
              hvEl.textContent = '—%';
              hvEl.className = 'text-lg font-bold text-gray-800';
              if (hvWin) hvWin.textContent = '—';
            }

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

          // ── Skew tooltip definitions ──────────────────────────────────
          var SKEW_TIPS = {
            put:  'Put IV (25δ)\\n\\n價外 Put 的隱含波動率。\\n數值越高代表市場願意付更多錢買下跌保護，\\n反映偏空情緒或避險需求強烈。',
            call: 'Call IV (25δ)\\n\\n價外 Call 的隱含波動率。\\n數值越高代表市場願意付更多溢價買上漲曝險，\\n反映偏多情緒或投機需求旺盛。',
            skew: 'Skew (pts)\\n\\nPut IV 減去 Call IV 的差值（單位：百分點）。\\n正值(+) → Put 比 Call 貴，市場偏空/避險。\\n負值(-) → Call 比 Put 貴，市場偏多/投機。',
            rank: 'Skew Rank\\n\\n當前 Skew 在過去歷史中的相對位置。\\n100 = 最偏空（Put 溢價最高）\\n0 = 最偏多（Call 溢價最高）\\n需累積≥5天資料才顯示指針。'
          };

          function initTooltip() {
            var tip = document.createElement('div');
            tip.id = 'iv-global-tip';
            tip.style.cssText = [
              'position:fixed', 'z-index:9999', 'display:none',
              'max-width:240px', 'background:#1e293b', 'color:#e2e8f0',
              'font-size:12px', 'line-height:1.55', 'white-space:pre-line',
              'padding:8px 10px', 'border-radius:8px',
              'box-shadow:0 4px 16px rgba(0,0,0,.35)',
              'pointer-events:none', 'transition:opacity .15s'
            ].join(';');
            document.body.appendChild(tip);

            var lastTipEl = null;

            function showTip(el, e) {
              var key = el.dataset.tipKey;
              if (!key || !SKEW_TIPS[key]) return;
              tip.textContent = SKEW_TIPS[key];
              tip.style.display = 'block';
              moveTip(e);
            }
            function moveTip(e) {
              var px = e.clientX + 14, py = e.clientY - 10;
              if (px + 250 > window.innerWidth) px = e.clientX - 254;
              if (py + tip.offsetHeight > window.innerHeight) py = e.clientY - tip.offsetHeight - 6;
              tip.style.left = px + 'px';
              tip.style.top  = py + 'px';
            }
            function hideTip() {
              tip.style.display = 'none';
              lastTipEl = null;
            }

            document.addEventListener('mouseover', function (e) {
              var el = e.target.closest('[data-tip-key]');
              if (!el) return;
              lastTipEl = el;
              showTip(el, e);
            });
            document.addEventListener('mousemove', function (e) {
              if (tip.style.display === 'none') return;
              moveTip(e);
            });
            document.addEventListener('mouseout', function (e) {
              var el = e.target.closest('[data-tip-key]');
              if (el) hideTip();
            });
            document.addEventListener('click', function (e) {
              var el = e.target.closest('[data-tip-key]');
              if (!el) { hideTip(); return; }
              if (lastTipEl === el && tip.style.display !== 'none') { hideTip(); return; }
              lastTipEl = el;
              showTip(el, e);
            });
          }

          // ── Dashboard ─────────────────────────────────────────────────
          var _dashMode = 'ivr'; // 'ivr' | 'skew'
          var _watchlistData = [];

          window.switchDashMode = function(mode) {
            _dashMode = mode;
            var ivrBtn  = document.getElementById('dash-mode-ivr');
            var skewBtn = document.getElementById('dash-mode-skew');
            if (mode === 'ivr') {
              ivrBtn.className  = 'px-3 py-1.5 bg-orange-500 text-white transition-colors';
              skewBtn.className = 'px-3 py-1.5 bg-white text-gray-600 hover:bg-gray-50 transition-colors';
            } else {
              ivrBtn.className  = 'px-3 py-1.5 bg-white text-gray-600 hover:bg-gray-50 transition-colors';
              skewBtn.className = 'px-3 py-1.5 bg-cyan-500 text-white transition-colors';
            }
            renderDashboard(_watchlistData, mode);
          };

          function degToXY(cx, cy, r, deg) {
            var rad = deg * Math.PI / 180;
            return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
          }

          function buildArcPath(cx, cy, r, startDeg, endDeg) {
            var s    = degToXY(cx, cy, r, startDeg);
            var e    = degToXY(cx, cy, r, endDeg);
            var large = (endDeg - startDeg) > 180 ? 1 : 0;
            return 'M' + s[0].toFixed(1) + ',' + s[1].toFixed(1) +
              ' A' + r + ',' + r + ' 0 ' + large + ' 1 ' +
              e[0].toFixed(1) + ',' + e[1].toFixed(1);
          }

          // Strategy label combining ivr + skew_rank
          function strategyInfo(ivr, skewRank) {
            var ivHigh = ivr !== null && ivr >= 60;
            var ivLow  = ivr !== null && ivr < 30;
            var skHigh = skewRank !== null && skewRank >= 60;
            var skLow  = skewRank !== null && skewRank < 30;
            if (ivr === null) return { text: '觀望', color: '#9ca3af' };
            if (ivHigh && skHigh) return { text: '適合賣 Call・偏空',  color: '#dc2626' };
            if (ivHigh && skLow)  return { text: '適合 CSP・偏多',     color: '#ea580c' };
            if (ivHigh)           return { text: '適合賣方・方向中性', color: '#ea580c' };
            if (ivLow  && skLow)  return { text: '適合買 Call',        color: '#16a34a' };
            if (ivLow  && skHigh) return { text: '適合買 Put',         color: '#dc2626' };
            return { text: '觀望', color: '#9ca3af' };
          }

          function ttsIcons(text) {
            var spk = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11" style="display:block"><path d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.707.707L4.586 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.586l3.707-3.707a1 1 0 011.09-.217zM12.293 7.293a1 1 0 011.414 1.414 3 3 0 010 4.243 1 1 0 01-1.414-1.414 1 1 0 000-1.415 1 1 0 010-1.414z"/></svg>';
            var s = 'background:none;border:none;cursor:pointer;padding:1px 2px;line-height:1;vertical-align:middle;display:inline-flex;align-items:center';
            return '<button class="card-tts-btn" data-tts-text="' + text + '" data-tts-gender="male" style="color:#3b82f6;' + s + '" title="男聲朗讀">' + spk + '</button>' +
                   '<button class="card-tts-btn" data-tts-text="' + text + '" data-tts-gender="female" style="color:#ef4444;' + s + '" title="女聲朗讀">' + spk + '</button>';
          }

          function buildGaugeCard(item, mode) {
            var W = 128, H = 86, cx = 64, cy = 68, r = 50, sw = 10;
            var isIvr = mode !== 'skew';

            // Rank value for this mode
            var rank = isIvr
              ? (item.ivr_1y  !== null && item.ivr_1y  !== undefined ? parseFloat(item.ivr_1y)  : null)
              : (item.skew_rank !== null && item.skew_rank !== undefined ? parseFloat(item.skew_rank) : null);

            // IV Rank: warm palette (orange/red border)
            // Skew Rank: cool palette (blue/cyan border)
            var needleColor, borderColor, segLow, segMid, segHigh;
            if (isIvr) {
              segLow  = '#2ecc8e'; segMid = '#e6952a'; segHigh = '#e05252';
              needleColor = rank === null ? '#9ca3af'
                : rank >= 60 ? '#e05252' : rank >= 30 ? '#e6952a' : '#2ecc8e';
              borderColor = rank === null ? '#e5e7eb'
                : rank >= 60 ? '#fecaca' : rank >= 30 ? '#fed7aa' : '#bbf7d0';
            } else {
              // Skew: >= 60 red, 30-60 gray, < 30 green
              segLow  = '#22d3ee'; segMid = '#94a3b8'; segHigh = '#f87171';
              needleColor = rank === null ? '#9ca3af'
                : rank >= 60 ? '#f87171' : rank >= 30 ? '#94a3b8' : '#22d3ee';
              borderColor = rank === null ? '#e5e7eb'
                : rank >= 60 ? '#fecaca' : rank >= 30 ? '#e2e8f0' : '#a5f3fc';
            }

            var svg = '';
            svg += '<path d="' + buildArcPath(cx, cy, r, 180, 360) +
              '" fill="none" stroke="#f3f4f6" stroke-width="' + sw + '" stroke-linecap="butt"/>';

            if (rank !== null) {
              svg += '<path d="' + buildArcPath(cx, cy, r, 180, 234) +
                '" fill="none" stroke="' + segLow + '" stroke-width="' + sw + '" stroke-linecap="butt"/>';
              svg += '<path d="' + buildArcPath(cx, cy, r, 234, 288) +
                '" fill="none" stroke="' + segMid + '" stroke-width="' + sw + '" stroke-linecap="butt"/>';
              svg += '<path d="' + buildArcPath(cx, cy, r, 288, 360) +
                '" fill="none" stroke="' + segHigh + '" stroke-width="' + sw + '" stroke-linecap="butt"/>';

              var ndeg = (180 + rank / 100 * 180) * Math.PI / 180;
              var nl   = r * 0.76;
              svg += '<line x1="' + cx + '" y1="' + cy + '"' +
                ' x2="' + (cx + nl * Math.cos(ndeg)).toFixed(1) + '"' +
                ' y2="' + (cy + nl * Math.sin(ndeg)).toFixed(1) + '"' +
                ' stroke="' + needleColor + '" stroke-width="2.5" stroke-linecap="round"/>';
              svg += '<circle cx="' + cx + '" cy="' + cy + '" r="3.5" fill="' + needleColor + '"/>';
            }

            svg += '<text x="' + cx + '" y="' + (cy + 16) + '"' +
              ' text-anchor="middle" font-size="15" font-weight="700" fill="' + needleColor + '">' +
              (rank !== null ? rank.toFixed(1) : '—') + '</text>';
            var rankTipHtml = !isIvr
              ? '<div style="text-align:center;margin-top:-12px;margin-bottom:2px">' +
                '<span data-tip-key="rank" style="cursor:pointer;color:#94a3b8;font-size:9px;user-select:none">❓ Skew Rank</span>' + ttsIcons('Skew Rank') +
                '</div>'
              : '';

            var lp = degToXY(cx, cy, r, 180);
            var rp = degToXY(cx, cy, r, 360);
            svg += '<text x="' + (lp[0] + 6).toFixed(0) + '" y="' + (lp[1] + 4).toFixed(0) +
              '" text-anchor="middle" font-size="7" fill="#9ca3af">0</text>';
            svg += '<text x="' + (rp[0] - 6).toFixed(0) + '" y="' + (rp[1] + 4).toFixed(0) +
              '" text-anchor="middle" font-size="7" fill="#9ca3af">100</text>';

            // Bottom details (10px gray)
            var detailLine;
            if (isIvr) {
              var atmStr = item.latest_atm_iv !== null && item.latest_atm_iv !== undefined
                ? 'ATM IV: ' + (parseFloat(item.latest_atm_iv) * 100).toFixed(1) + '%'
                : (rank === null ? '尚無資料' : '');
              detailLine = '<div style="text-align:center;font-size:10px;color:#9ca3af;margin-top:-2px">' + atmStr + ttsIcons('ATM IV') + '</div>';
            } else {
              var putStr  = item.put_iv_025  !== null && item.put_iv_025  !== undefined
                ? (parseFloat(item.put_iv_025)  * 100).toFixed(1) + '%' : '—';
              var callStr = item.call_iv_025 !== null && item.call_iv_025 !== undefined
                ? (parseFloat(item.call_iv_025) * 100).toFixed(1) + '%' : '—';
              var skewStr = item.skew_pts    !== null && item.skew_pts    !== undefined
                ? (parseFloat(item.skew_pts) >= 0 ? '+' : '') + parseFloat(item.skew_pts).toFixed(1) + ' pts' : '—';
              var tipStyle = 'cursor:pointer;color:#94a3b8;font-size:9px;vertical-align:middle;margin-left:2px;user-select:none';
              detailLine =
                '<div style="text-align:center;font-size:10px;color:#9ca3af;margin-top:-2px">' +
                  'Put: ' + putStr +
                  '<span data-tip-key="put" style="' + tipStyle + '">❓</span>' + ttsIcons('Put') +
                  ' | Call: ' + callStr +
                  '<span data-tip-key="call" style="' + tipStyle + '">❓</span>' + ttsIcons('Call') +
                '</div>' +
                '<div style="text-align:center;font-size:10px;color:#9ca3af">' +
                  'Skew: ' + skewStr +
                  '<span data-tip-key="skew" style="' + tipStyle + '">❓</span>' + ttsIcons('Skew') +
                '</div>';
            }

            // Strategy label
            var ivr   = item.ivr_1y    !== null && item.ivr_1y    !== undefined ? parseFloat(item.ivr_1y)    : null;
            var srank = item.skew_rank !== null && item.skew_rank !== undefined ? parseFloat(item.skew_rank) : null;
            var strat = strategyInfo(ivr, srank);
            var stratDiv = '<div style="text-align:center;font-size:11px;font-weight:700;color:' +
              strat.color + ';margin-top:3px;padding-bottom:2px">' + strat.text + '</div>';

            return '<div class="iv-dash-card" data-ticker="' + item.ticker + '" style="' +
              'border:2px solid ' + borderColor + ';border-radius:12px;padding:6px 4px 4px;' +
              'background:#fff;width:128px;cursor:pointer;transition:box-shadow .15s,transform .15s;' +
              'box-sizing:border-box">' +
              '<div style="font-size:0.75rem;font-weight:700;color:#374151;text-align:center;margin-bottom:1px">' +
              item.ticker + '</div>' +
              '<svg width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + ' ' + H + '">' + svg + '</svg>' +
              rankTipHtml +
              detailLine +
              stratDiv +
              '</div>';
          }

          function renderDashboard(list, mode) {
            var summaryEl = document.getElementById('iv-dashboard-summary');
            var cardsEl   = document.getElementById('iv-dashboard-cards');
            var isIvr     = mode !== 'skew';

            // Update summary bar labels
            if (isIvr) {
              document.getElementById('dash-sum-high-label').textContent = 'High Vol · IVR ≥ 60';
              document.getElementById('dash-sum-mid-label').textContent  = 'Neutral · 30–60';
              document.getElementById('dash-sum-low-label').textContent  = 'Low Vol · IVR < 30';
              document.getElementById('dash-sum-high-box').className = 'rounded-lg p-3 text-center bg-red-50';
              document.getElementById('dash-sum-mid-box').className  = 'rounded-lg p-3 text-center bg-gray-50';
              document.getElementById('dash-sum-low-box').className  = 'rounded-lg p-3 text-center bg-green-50';
              document.getElementById('dash-sum-high-label').className = 'text-xs font-medium text-red-700';
              document.getElementById('dash-sum-mid-label').className  = 'text-xs font-medium text-gray-600';
              document.getElementById('dash-sum-low-label').className  = 'text-xs font-medium text-green-700';
              document.getElementById('iv-summary-high-count').className = 'text-2xl font-bold text-red-600 mt-1';
              document.getElementById('iv-summary-mid-count').className  = 'text-2xl font-bold text-gray-500 mt-1';
              document.getElementById('iv-summary-low-count').className  = 'text-2xl font-bold text-green-600 mt-1';
            } else {
              document.getElementById('dash-sum-high-label').textContent = 'High Put Skew ≥ 60';
              document.getElementById('dash-sum-mid-label').textContent  = 'Balanced Skew 30–60';
              document.getElementById('dash-sum-low-label').textContent  = 'Low Put Skew < 30';
              document.getElementById('dash-sum-high-box').className = 'rounded-lg p-3 text-center bg-red-50';
              document.getElementById('dash-sum-mid-box').className  = 'rounded-lg p-3 text-center bg-slate-50';
              document.getElementById('dash-sum-low-box').className  = 'rounded-lg p-3 text-center bg-cyan-50';
              document.getElementById('dash-sum-high-label').className = 'text-xs font-medium text-red-700';
              document.getElementById('dash-sum-mid-label').className  = 'text-xs font-medium text-slate-500';
              document.getElementById('dash-sum-low-label').className  = 'text-xs font-medium text-cyan-700';
              document.getElementById('iv-summary-high-count').className = 'text-2xl font-bold text-red-600 mt-1';
              document.getElementById('iv-summary-mid-count').className  = 'text-2xl font-bold text-slate-500 mt-1';
              document.getElementById('iv-summary-low-count').className  = 'text-2xl font-bold text-cyan-600 mt-1';
            }

            if (!list || !list.length) {
              cardsEl.innerHTML = '<span style="font-size:.875rem;color:#9ca3af;padding:1rem 0">查詢後自動加入 Watchlist</span>';
              summaryEl.classList.add('hidden');
              return;
            }

            // Summary counts
            var rankKey = isIvr ? 'ivr_1y' : 'skew_rank';
            var withRank = list.filter(function(d) { return d[rankKey] !== null && d[rankKey] !== undefined; });
            var high = withRank.filter(function(d) { return parseFloat(d[rankKey]) >= 60; }).length;
            var mid  = withRank.filter(function(d) { var v = parseFloat(d[rankKey]); return v >= 30 && v < 60; }).length;
            var low  = withRank.filter(function(d) { return parseFloat(d[rankKey]) < 30; }).length;

            document.getElementById('iv-summary-high-count').textContent = high;
            document.getElementById('iv-summary-mid-count').textContent  = mid;
            document.getElementById('iv-summary-low-count').textContent  = low;
            summaryEl.classList.remove('hidden');

            var sorted = list.slice().sort(function(a, b) {
              var ra = a[rankKey] !== null && a[rankKey] !== undefined ? parseFloat(a[rankKey]) : -1;
              var rb = b[rankKey] !== null && b[rankKey] !== undefined ? parseFloat(b[rankKey]) : -1;
              return rb - ra;
            });

            cardsEl.innerHTML = sorted.map(function(item) { return buildGaugeCard(item, mode); }).join('');

            cardsEl.querySelectorAll('.iv-dash-card').forEach(function(card) {
              card.addEventListener('click', function() {
                var ticker = card.dataset.ticker;
                document.getElementById('iv-ticker').value = ticker;
                loadExpirations(ticker);
                document.getElementById('iv-analysis-form').scrollIntoView({ behavior: 'smooth', block: 'start' });
              });
              card.addEventListener('mouseover', function() {
                card.style.boxShadow = '0 4px 12px rgba(0,0,0,.12)';
                card.style.transform = 'translateY(-2px)';
              });
              card.addEventListener('mouseout', function() {
                card.style.boxShadow = '';
                card.style.transform = '';
              });
            });
            cardsEl.querySelectorAll('.card-tts-btn').forEach(function(btn) {
              btn.addEventListener('click', function(e) {
                e.stopPropagation();
                if (typeof window.ttsSpeak === 'function') window.ttsSpeak(btn.dataset.ttsText, btn.dataset.ttsGender);
              });
            });
          }

          // Mode toggle buttons
          document.getElementById('dash-mode-ivr').addEventListener('click', function() { switchDashMode('ivr'); });
          document.getElementById('dash-mode-skew').addEventListener('click', function() { switchDashMode('skew'); });

          function loadWatchlist() {
            fetch('/api/iv_analysis/watchlist')
              .then(function (r) { return r.json(); })
              .then(function (data) {
                _watchlistData = data.watchlist || [];
                renderWatchlist(_watchlistData);
                renderDashboard(_watchlistData, _dashMode);
              })
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

          initTooltip();
          loadWatchlist();
        })();
      JS
    end
  end
end
