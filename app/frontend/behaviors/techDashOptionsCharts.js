/**
 * 技術面儀表板：期權相關圖表。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.symbol
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var sym = root.dataset.symbol;

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
            { label: d.volume_oi_filter === 'volume' ? 'Call Vol' : 'Call OI', data: d.call_oi,
              backgroundColor: 'rgba(59,130,246,0.65)', borderColor: 'rgba(37,99,235,0.8)',
              borderWidth: 1, borderRadius: 2 },
            { label: d.volume_oi_filter === 'volume' ? 'Put Vol' : 'Put OI', data: d.put_oi,
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
                  '<div style="color:#2563eb;">' + (d.volume_oi_filter === 'volume' ? 'Call Vol: ' : 'Call OI: ') + fmt(callOI) + '</div>' +
                  '<div style="color:#ea580c;">' + (d.volume_oi_filter === 'volume' ? 'Put Vol: ' : 'Put OI: ') + fmt(putOI) + '</div>';
              }
            }
          },
          vlines: d.last_price ? [{ value: d.last_price, color: 'rgba(107,114,128,0.6)', dash: [4,3], label: 'Last $' + d.last_price.toFixed(2) }] : [],
          scales: {
            x: { ticks: Object.assign({}, TICK, { maxRotation: 45 }), grid: { color: GRID } },
            y: { title: { display: true, text: d.volume_oi_filter === 'volume' ? 'Volume' : 'Open Interest', color: '#9ca3af', font: { size: 11 } }, ticks: TICK, grid: { color: GRID } }
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
}
